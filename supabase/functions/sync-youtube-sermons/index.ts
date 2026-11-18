import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const channelHandleUrl = "https://www.youtube.com/@RCZKanyamacongregation";
const channelStreamsUrl = `${channelHandleUrl}/streams`;
const knownChannelId = "UCycolpgl3NjWvE7XmpV4KCA";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type SermonEntry = {
  id: string;
  youtube_video_id: string;
  title: string;
  thumbnail_url: string;
  published_at: string | null;
  is_live: boolean;
  scheduled_start: string | null;
};

type LiveInfo = {
  title?: string;
  isLive: boolean;
  isUpcoming: boolean;
  scheduledStart: string | null;
};

const userAgent = "RCZ-Kanyama-App/1.1";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST is required" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    // The public channel id is stable. Use it directly for the RSS feed and
    // only fall back to resolving the handle if YouTube rejects the request.
    const rssUrl = (channelId: string) =>
      `https://www.youtube.com/feeds/videos.xml?channel_id=${channelId}`;

    const [initialRssResponse, streamsResponse] = await Promise.all([
      fetch(rssUrl(knownChannelId), { headers: { "User-Agent": userAgent } }),
      fetch(channelStreamsUrl, { headers: { "User-Agent": userAgent } }),
    ]);

    let rssResponse = initialRssResponse;
    if (!rssResponse.ok) {
      const channelResponse = await fetch(channelHandleUrl, {
        headers: { "User-Agent": userAgent },
      });
      if (channelResponse.ok) {
        const channelHtml = await channelResponse.text();
        const resolvedId =
          channelHtml.match(/"externalId":"(UC[A-Za-z0-9_-]+)"/)?.[1] ??
          channelHtml.match(/"channelId":"(UC[A-Za-z0-9_-]+)"/)?.[1];
        if (resolvedId && resolvedId !== knownChannelId) {
          rssResponse = await fetch(rssUrl(resolvedId), {
            headers: { "User-Agent": userAgent },
          });
        }
      }
    }

    if (!rssResponse.ok) {
      throw new Error(`YouTube RSS feed returned ${rssResponse.status}`);
    }

    const rssXml = await rssResponse.text();
    const rssEntries = parseRss(rssXml);
    if (rssEntries.length === 0) {
      throw new Error("The YouTube RSS feed returned no videos");
    }

    // Live and scheduled streams are best-effort. If YouTube changes its page
    // markup the sync still succeeds with the RSS-backed published videos.
    let streamInfo = new Map<string, LiveInfo>();
    if (streamsResponse.ok) {
      try {
        streamInfo = parseStreamPage(await streamsResponse.text());
      } catch (error) {
        console.warn("Live stream page could not be parsed:", error);
      }
    }

    const merged = new Map<string, SermonEntry>();
    for (const entry of rssEntries) {
      merged.set(entry.id, {
        id: entry.id,
        youtube_video_id: entry.id,
        title: entry.title,
        thumbnail_url: `https://img.youtube.com/vi/${entry.id}/mqdefault.jpg`,
        published_at: entry.publishedAt,
        is_live: false,
        scheduled_start: null,
      });
    }

    for (const [videoId, info] of streamInfo) {
      if (!info.isLive && !info.isUpcoming) continue;
      const existing = merged.get(videoId);
      merged.set(videoId, {
        id: videoId,
        youtube_video_id: videoId,
        title: existing?.title ?? info.title ?? "RCZ - Kanyama service",
        thumbnail_url:
          existing?.thumbnail_url ??
          `https://img.youtube.com/vi/${videoId}/mqdefault.jpg`,
        // An upcoming stream has no publication date yet; its scheduled start
        // is kept separately and must never be treated as "newest published".
        published_at: info.isUpcoming ? null : existing?.published_at ?? null,
        is_live: info.isLive,
        scheduled_start: info.scheduledStart,
      });
    }

    // Keep live first, then upcoming by start time, then published uploads
    // newest-first by the real YouTube publication timestamp. The database is
    // ordered by the client as a final safety net.
    const now = Date.now();
    const entries = [...merged.values()]
      .sort((a, b) => {
        if (a.is_live !== b.is_live) return a.is_live ? -1 : 1;
        if (a.is_live) return 0;
        const aUpcoming =
          a.published_at == null &&
          a.scheduled_start != null &&
          Date.parse(a.scheduled_start) > now;
        const bUpcoming =
          b.published_at == null &&
          b.scheduled_start != null &&
          Date.parse(b.scheduled_start) > now;
        if (aUpcoming !== bUpcoming) return aUpcoming ? -1 : 1;
        if (aUpcoming && bUpcoming) {
          return Date.parse(a.scheduled_start!) -
            Date.parse(b.scheduled_start!);
        }
        const aDate = a.published_at ?? a.scheduled_start;
        const bDate = b.published_at ?? b.scheduled_start;
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.localeCompare(aDate);
      })
      .slice(0, 25);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    let warning: string | null = null;
    let { error } = await supabase.from("sermons").upsert(entries, {
      onConflict: "id",
    });

    // The live columns are additive. Until the corrective SQL has been run,
    // fall back to the original columns rather than breaking the sync.
    if (error && isMissingLiveColumn(error)) {
      warning =
        "The sermons table does not yet have is_live/scheduled_start. Publication timestamps were still updated.";
      const basicEntries = entries.map(({ is_live: _isLive, scheduled_start: _scheduled, ...rest }) => rest);
      const retry = await supabase.from("sermons").upsert(basicEntries, {
        onConflict: "id",
      });
      error = retry.error;
    }
    if (error) throw error;

    // A stream that has ended must stop showing a LIVE badge even if it has
    // dropped out of the RSS window. This cleanup is skipped when the live
    // columns are not installed yet.
    if (!warning) {
      try {
        const { data: liveRows, error: liveError } = await supabase
          .from("sermons")
          .select("id")
          .eq("is_live", true);
        if (!liveError) {
          const activeLive = new Set(
            entries.filter((entry) => entry.is_live).map((entry) => entry.id),
          );
          const staleLive = (liveRows ?? [])
            .map((row) => row.id as string)
            .filter((id) => !activeLive.has(id));
          if (staleLive.length > 0) {
            await supabase
              .from("sermons")
              .update({ is_live: false })
              .in("id", staleLive);
          }
        }
      } catch (cleanupError) {
        console.warn("Stale live sermon cleanup failed:", cleanupError);
      }
    }

    return new Response(
      JSON.stringify({
        synced: entries.length,
        live: entries.filter((entry) => entry.is_live).length,
        upcoming: entries.filter((entry) => entry.scheduled_start && !entry.is_live).length,
        warning,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("YouTube sermon sync failed:", error);
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : "Sync failed" }),
      {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

function isMissingLiveColumn(error: { code?: string; message?: string }): boolean {
  const message = (error.message ?? "").toLowerCase();
  return (
    error.code === "42703" ||
    message.includes("is_live") ||
    message.includes("scheduled_start")
  );
}

function parseRss(xml: string): Array<{ id: string; title: string; publishedAt: string | null }> {
  const results: Array<{ id: string; title: string; publishedAt: string | null }> = [];
  const seen = new Set<string>();
  for (const match of xml.matchAll(/<entry>([\s\S]*?)<\/entry>/g)) {
    const block = match[1];
    const id = block.match(/<yt:videoId>\s*([^<\s]+)\s*<\/yt:videoId>/)?.[1];
    if (!id || seen.has(id)) continue;
    const title = decodeXml(
      block.match(/<title>([\s\S]*?)<\/title>/)?.[1]?.trim() ?? "RCZ - Kanyama service",
    );
    const publishedRaw = block.match(/<published>([\s\S]*?)<\/published>/)?.[1]?.trim();
    const published = normalizeDate(publishedRaw);
    seen.add(id);
    results.push({ id, title, publishedAt: published });
  }
  return results;
}

function parseStreamPage(html: string): Map<string, LiveInfo> {
  const result = new Map<string, LiveInfo>();
  const matches = [...html.matchAll(/"videoId":"([A-Za-z0-9_-]{11})"/g)];
  for (let index = 0; index < matches.length; index++) {
    const id = matches[index][1];
    const start = matches[index].index ?? 0;
    const end = index + 1 < matches.length
      ? matches[index + 1].index ?? Math.min(start + 6000, html.length)
      : Math.min(start + 6000, html.length);
    const chunk = html.slice(start, end);
    const isLive =
      /"isLive":true/.test(chunk) ||
      /"isLiveNow":true/.test(chunk) ||
      /"style":"LIVE"/.test(chunk) ||
      /"simpleText":"LIVE"/.test(chunk);
    const isUpcoming =
      /"style":"UPCOMING"/.test(chunk) ||
      /"simpleText":"UPCOMING"/.test(chunk) ||
      /"upcomingEventData"/.test(chunk);
    if (!isLive && !isUpcoming) continue;
    const title = extractTitle(chunk);
    const startSeconds = chunk.match(
      /"(?:startTime|scheduledStartTime)":"?(\d{9,12})"?/,
    )?.[1];
    result.set(id, {
      title,
      isLive,
      isUpcoming,
      scheduledStart: startSeconds
        ? normalizeDate(
          new Date(Number(startSeconds) * 1000).toISOString(),
        )
        : null,
    });
  }
  return result;
}

function extractTitle(chunk: string): string | undefined {
  const runs = chunk.match(/"title":\{"runs":\[\{"text":"([^"]+)"/)?.[1];
  const simple = chunk.match(/"title":\{"simpleText":"([^"]+)"/)?.[1];
  const value = runs ?? simple;
  return value ? decodeXml(value) : undefined;
}

function normalizeDate(value: string | undefined): string | null {
  if (!value) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

function decodeXml(value: string): string {
  return value
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#x27;/g, "'")
    .replace(/&#x2F;/g, "/");
}
