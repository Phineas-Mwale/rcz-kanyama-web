$ErrorActionPreference = "Stop"

$source = "tools\bible_web\world-english-bible-master\json"
$output = "tools\bible_web\output"
$package = Join-Path $output "web_package"
$zipPath = Join-Path $output "web-1.0.0.zip"

# Canonical Protestant Bible book order.
# Format: filename|OSIS ID|English name|testament

$definitions = @(
"genesis|Gen|Genesis|old"
"exodus|Exod|Exodus|old"
"leviticus|Lev|Leviticus|old"
"numbers|Num|Numbers|old"
"deuteronomy|Deut|Deuteronomy|old"
"joshua|Josh|Joshua|old"
"judges|Judg|Judges|old"
"ruth|Ruth|Ruth|old"
"1samuel|1Sam|1 Samuel|old"
"2samuel|2Sam|2 Samuel|old"
"1kings|1Kgs|1 Kings|old"
"2kings|2Kgs|2 Kings|old"
"1chronicles|1Chr|1 Chronicles|old"
"2chronicles|2Chr|2 Chronicles|old"
"ezra|Ezra|Ezra|old"
"nehemiah|Neh|Nehemiah|old"
"esther|Esth|Esther|old"
"job|Job|Job|old"
"psalms|Ps|Psalms|old"
"proverbs|Prov|Proverbs|old"
"ecclesiastes|Eccl|Ecclesiastes|old"
"songofsolomon|Song|Song of Solomon|old"
"isaiah|Isa|Isaiah|old"
"jeremiah|Jer|Jeremiah|old"
"lamentations|Lam|Lamentations|old"
"ezekiel|Ezek|Ezekiel|old"
"daniel|Dan|Daniel|old"
"hosea|Hos|Hosea|old"
"joel|Joel|Joel|old"
"amos|Amos|Amos|old"
"obadiah|Obad|Obadiah|old"
"jonah|Jonah|Jonah|old"
"micah|Mic|Micah|old"
"nahum|Nah|Nahum|old"
"habakkuk|Hab|Habakkuk|old"
"zephaniah|Zeph|Zephaniah|old"
"haggai|Hag|Haggai|old"
"zechariah|Zech|Zechariah|old"
"malachi|Mal|Malachi|old"
"matthew|Matt|Matthew|new"
"mark|Mark|Mark|new"
"luke|Luke|Luke|new"
"john|John|John|new"
"acts|Acts|Acts|new"
"romans|Rom|Romans|new"
"1corinthians|1Cor|1 Corinthians|new"
"2corinthians|2Cor|2 Corinthians|new"
"galatians|Gal|Galatians|new"
"ephesians|Eph|Ephesians|new"
"philippians|Phil|Philippians|new"
"colossians|Col|Colossians|new"
"1thessalonians|1Thess|1 Thessalonians|new"
"2thessalonians|2Thess|2 Thessalonians|new"
"1timothy|1Tim|1 Timothy|new"
"2timothy|2Tim|2 Timothy|new"
"titus|Titus|Titus|new"
"philemon|Phlm|Philemon|new"
"hebrews|Heb|Hebrews|new"
"james|Jas|James|new"
"1peter|1Pet|1 Peter|new"
"2peter|2Pet|2 Peter|new"
"1john|1John|1 John|new"
"2john|2John|2 John|new"
"3john|3John|3 John|new"
"jude|Jude|Jude|new"
"revelation|Rev|Revelation|new"
)

if (-not (Test-Path $source)) {
    throw "WEB source folder not found: $source"
}

if ((Get-ChildItem $source -Filter *.json).Count -ne 66) {
    throw "Expected exactly 66 WEB source files."
}

# Start with a clean output directory.
if (Test-Path $output) {
    Remove-Item $output -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $package | Out-Null

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$manifestBooks = @()
$totalChapters = 0
$totalVerses = 0

Write-Host "`nConverting World English Bible..." -ForegroundColor Cyan

foreach ($definition in $definitions) {
    $parts = $definition.Split("|")
    $bookId = $parts[0]
    $osisId = $parts[1]
    $bookName = $parts[2]
    $testament = $parts[3]

    $sourceFile = Join-Path $source "$bookId.json"

    if (-not (Test-Path $sourceFile)) {
        throw "Missing source file: $sourceFile"
    }

    Write-Host "Processing $bookName..."

    $jsonContent = Get-Content $sourceFile -Raw -Encoding UTF8
    $records = ConvertFrom-Json -InputObject $jsonContent

    # Chapter -> verse -> ordered text fragments.
    $chapters = @{}

    foreach ($record in $records) {
        if ($record.type -notin @("paragraph text", "line text")) {
            continue
        }

        if ($null -eq $record.chapterNumber -or
            $null -eq $record.verseNumber -or
            $null -eq $record.value) {
            continue
        }

        $chapterNumber = [int]$record.chapterNumber
        $verseNumber = [int]$record.verseNumber
        $value = [string]$record.value

        if ($chapterNumber -lt 1 -or $verseNumber -lt 1) {
            throw "Invalid chapter or verse in $bookName."
        }

        if (-not $chapters.ContainsKey($chapterNumber)) {
            $chapters[$chapterNumber] = @{}
        }

        $chapterVerses = $chapters[$chapterNumber]

        if (-not $chapterVerses.ContainsKey($verseNumber)) {
            $chapterVerses[$verseNumber] =
                New-Object 'System.Collections.Generic.List[string]'
        }

        $chapterVerses[$verseNumber].Add($value)
    }

    if ($chapters.Count -eq 0) {
        throw "No Bible verses found in $bookName."
    }

    $chapterNumbers = @(
        $chapters.Keys | Sort-Object { [int]$_ }
    )

    # Check that chapters are numbered consecutively.
    for ($i = 0; $i -lt $chapterNumbers.Count; $i++) {
        if ([int]$chapterNumbers[$i] -ne ($i + 1)) {
            throw "Missing chapter in $bookName near chapter $($i + 1)."
        }
    }

    foreach ($chapterNumber in $chapterNumbers) {
        $chapterVerses = $chapters[$chapterNumber]
        $verseNumbers = @(
            $chapterVerses.Keys | Sort-Object { [int]$_ }
        )

        if ($verseNumbers.Count -eq 0) {
            throw "Empty chapter: $bookName $chapterNumber."
        }

        $verseRows = @()

        foreach ($verseNumber in $verseNumbers) {
            $fragments = $chapterVerses[$verseNumber]
            $builder = New-Object System.Text.StringBuilder

            # Preserve source whitespace where possible.
            # Add a separating space only when two fragments
            # would otherwise run together.
            foreach ($fragment in $fragments) {
                $piece = [string]$fragment

                if ($builder.Length -gt 0 -and
                    $piece.Length -gt 0) {
                    $last = $builder[$builder.Length - 1]
                    $first = $piece[0]

                    if (-not [char]::IsWhiteSpace($last) -and
                        -not [char]::IsWhiteSpace($first)) {
                        [void]$builder.Append(" ")
                    }
                }

                [void]$builder.Append($piece)
            }

            $verseText = $builder.ToString().Trim()

            # Some WEB verses are intentionally omitted in the source.
            # Do not invent text or include empty verse entries.
            if ([string]::IsNullOrWhiteSpace($verseText)) {
                Write-Host "  Skipping intentionally empty verse: $bookName $chapterNumber`:$verseNumber" -ForegroundColor DarkYellow
                continue
            }

            $verseRows += [ordered]@{
                number = [int]$verseNumber
                text = $verseText
            }

            $totalVerses++
        }

        $chapterObject = [ordered]@{
            bookId = $bookId
            chapter = [int]$chapterNumber
            verses = $verseRows
        }

        $bookFolder = Join-Path $package "books\$bookId"
        New-Item -ItemType Directory -Force -Path $bookFolder |
            Out-Null

        $chapterPath = Join-Path $bookFolder "$chapterNumber.json"
        $chapterJson = $chapterObject | ConvertTo-Json -Depth 10

        [System.IO.File]::WriteAllText(
            $chapterPath,
            $chapterJson,
            $utf8NoBom
        )

        $totalChapters++
    }

    $manifestBooks += [ordered]@{
        id = $bookId
        osisId = $osisId
        name = $bookName
        englishName = $bookName
        testament = $testament
        chapterCount = $chapterNumbers.Count
    }
}

if ($manifestBooks.Count -ne 66) {
    throw "Expected 66 books; generated $($manifestBooks.Count)."
}

if ($totalChapters -ne 1189) {
    throw "Expected 1189 chapters; generated $totalChapters. Stop and inspect."
}

$manifest = [ordered]@{
    schemaVersion = 1
    translation = [ordered]@{
        id = "web"
        name = "World English Bible"
        shortName = "WEB"
        languageCode = "en"
        languageName = "English"
        version = "1.0.0"
        description = "World English Bible for offline reading in RCZ Kanyama."
        attribution = "World English Bible (WEB), public domain."
        license = "Public domain"
        sourceRepository = "https://github.com/TehShrike/world-english-bible"
        contentVersion = "1.0.0"
    }
    books = $manifestBooks
}

$manifestJson = $manifest | ConvertTo-Json -Depth 15

[System.IO.File]::WriteAllText(
    (Join-Path $package "manifest.json"),
    $manifestJson,
    $utf8NoBom
)

$attribution = @"
World English Bible (WEB)

The World English Bible text is in the public domain.

Source data:
https://github.com/TehShrike/world-english-bible

Official WEB website:
https://worldenglish.bible/

Translation: World English Bible
Language: English
Version: 1.0.0

Packaged for offline reading in RCZ Kanyama.
"@

[System.IO.File]::WriteAllText(
    (Join-Path $package "ATTRIBUTION.txt"),
    $attribution,
    $utf8NoBom
)

# Validate package size and file count against installer limits.
$packageFiles = @(Get-ChildItem $package -Recurse -File)
$expandedBytes = (
    $packageFiles | Measure-Object Length -Sum
).Sum

if ($packageFiles.Count -gt 2500) {
    throw "Package exceeds the 2500-file installer limit."
}

if ($expandedBytes -gt 25MB) {
    throw "Package exceeds the 25 MB expanded-size installer limit."
}

# Create the ZIP with package contents at its root.
Compress-Archive `
    -Path "$package\*" `
    -DestinationPath $zipPath `
    -CompressionLevel Optimal `
    -Force

$hash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLower()
$zipBytes = (Get-Item $zipPath).Length

Write-Host "`n===== WEB PACKAGE CREATED =====" -ForegroundColor Green
Write-Host "Books:          $($manifestBooks.Count)"
Write-Host "Chapters:       $totalChapters"
Write-Host "Verses:         $totalVerses"
Write-Host "Package files:  $($packageFiles.Count)"
Write-Host "Expanded size:  $([math]::Round($expandedBytes / 1MB, 2)) MB"
Write-Host "ZIP size:       $([math]::Round($zipBytes / 1MB, 2)) MB"
Write-Host "SHA256:         $hash"
Write-Host "ZIP:            $zipPath" -ForegroundColor Cyan

Write-Host "`n===== CATALOG ENTRY VALUES ====="
Write-Host "id: web"
Write-Host "name: World English Bible"
Write-Host "shortName: WEB"
Write-Host "languageCode: en"
Write-Host "status: available"
Write-Host "version: 1.0.0"
Write-Host "packagePath: translations/web-1.0.0.zip"
Write-Host "sha256: $hash"
Write-Host "packageBytes: $zipBytes"
Write-Host "licenseLabel: Public domain"
