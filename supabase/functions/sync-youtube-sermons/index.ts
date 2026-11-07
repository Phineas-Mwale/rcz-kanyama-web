import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const channelUrl = `https://www.youtube.com/@RCZKanyamacongregation/videos`;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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
    const response = await fetch(channelUrl, {
      headers: { "User-Agent": "RCZ-Kanyama-App/1.0" },
    });
    if (!response.ok) {
      throw new Error(`YouTube feed returned ${response.status}`);
    }

    const html = await response.text();
    const entries = [];
    const pattern =
      /"videoId":"([^"]+)".{0,5000}?"title":\{"content":"([^"]+)"/gs;
    for (const match of html.matchAll(pattern)) {
      const videoId = match[1];
      const title = match[2];
      if (!entries.some((entry) => entry.id === videoId)) {
        entries.push({
          id: videoId,
          youtube_video_id: videoId,
          title: title === "Save to playlist"
            ? "RCZ - Kanyama service"
            : title,
          published_at: null,
          thumbnail_url: `https://img.youtube.com/vi/${videoId}/mqdefault.jpg`,
        });
      }
      if (entries.length >= 10) break;
    }

    if (entries.length === 0) {
      throw new Error("The YouTube channel returned no videos");
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { error } = await supabase.from("sermons").upsert(entries, {
      onConflict: "id",
    });
    if (error) throw error;

    return new Response(JSON.stringify({ synced: entries.length }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
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
