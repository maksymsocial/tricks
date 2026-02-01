# ==============================================================================
# SCRIPT CONFIGURATION
# ==============================================================================

# --- Ensure strict mode for better error detection ---
Set-StrictMode -Version Latest

# --- Path to the FFmpeg executable
$ffmpegPath = "C:\ffmpeg\bin\ffmpeg.exe"

# --- Git commit message
$commitMessage = "Add new trick(s)"

# --- Video quality settings for LQ version
# Lower CRF value means higher quality. 17-28 is a good range. 28 is good for previews.
$lqCrf = "28"
# Resolution for the low-quality preview video (e.g., "480" for 480p width)
$lqResolution = "480"


# ==============================================================================
# SCRIPT LOGIC
# ==============================================================================

Write-Host "Starting video processing script..."

# --- 1. Set up paths and directories ---
$baseDir = $PSScriptRoot
$rawDir = Join-Path $baseDir "raw"
$vidHQDir = Join-Path $baseDir "vidHQ"
$vidLQDir = Join-Path $baseDir "vidLQ"
$previewsDir = Join-Path $baseDir "previews"

Write-Host "Base Directory: $baseDir"

# Create directories if they don't exist
$dirsToCreate = @($rawDir, $vidHQDir, $vidLQDir, $previewsDir)
foreach ($dir in $dirsToCreate) {
    if (-not (Test-Path $dir)) {
        Write-Host "Attempting to create directory: $dir"
        try {
            New-Item -ItemType Directory -Path $dir -ErrorAction Stop | Out-Null
            Write-Host "Successfully created directory: $dir"
        } catch {
            Write-Error "Failed to create directory ${dir}: ${Error.Exception.Message}"
            exit 1 # Exit script on critical failure
        }
    } else {
        Write-Host "Directory already exists: $dir"
    }
}

# --- Validate FFmpeg path ---
if (-not (Test-Path $ffmpegPath)) {
    Write-Error "FFmpeg executable not found at '$ffmpegPath'. Please ensure FFmpeg is installed and the path is correct."
    exit 1
} else {
    Write-Host "FFmpeg found at: $ffmpegPath"
}

# --- 2. Find the last used video number ---
$lastNumber = 0
try {
    $existingVideos = Get-ChildItem -Path $vidHQDir -Filter "*.mp4" -ErrorAction Stop
    if ($existingVideos) {
        $lastVideo = $existingVideos | Sort-Object { [int]($_.BaseName) } | Select-Object -Last 1
        if ($lastVideo) {
            $lastNumber = [int]$lastVideo.BaseName
        }
    }
} catch {
    Write-Warning "Could not read existing videos from $vidHQDir (possibly empty or permissions issue): ${Error.Exception.Message}. Starting video numbering from 0."
    $lastNumber = 0 # Ensure it starts from 0 if error reading
}

Write-Host "Last video number found: $lastNumber. Starting new videos from $($lastNumber + 1)."

# --- 3. Process new videos from the 'raw' folder ---
$rawFiles = @(Get-ChildItem -Path $rawDir -Filter "*.mp4" -ErrorAction SilentlyContinue)
if (-not $rawFiles -or $rawFiles.Count -eq 0) {
    Write-Host "No new videos found in 'raw' folder to process."
} else {
    foreach ($rawFile in $rawFiles) {
        $newFilesAdded = $true
        $lastNumber++
        $newName = "$lastNumber"
        
        Write-Host "--- Processing new raw file $($rawFile.Name) -> $newName.mp4 ---"
        
        # Define new file paths
        $hqPath = Join-Path $vidHQDir "$newName.mp4"
        $lqPath = Join-Path $vidLQDir "$newName.mp4"
        $previewPath = Join-Path $previewsDir "$newName.jpg"
        
        # --- 3a. Copy raw video to vidHQ ---
        Write-Host "  -> Copying to High Quality folder..."
        try {
            Copy-Item -Path $rawFile.FullName -Destination $hqPath -ErrorAction Stop
            Write-Host "  -> HQ copy successful."
        } catch {
            Write-Error "  -> Failed to copy '$($rawFile.Name)' to '$hqPath': ${Error.Exception.Message}"
            continue # Skip to next raw file
        }
        
        # --- 3b. Create Low Quality version with FFmpeg ---
        Write-Host "  -> Creating Low Quality version..."
        try {
            $ffmpegArgsLQ = "-i `"$hqPath`" -vf `"scale=${lqResolution}:-1`" -c:v libx264 -preset veryfast -crf $lqCrf `"$lqPath`""
            & $ffmpegPath $ffmpegArgsLQ 2>&1 | Out-Null # Redirect stderr to null
            Write-Host "  -> LQ conversion successful."
        } catch {
            Write-Error "  -> Failed to create LQ version for '$($rawFile.Name)': ${Error.Exception.Message}"
            continue # Skip to next raw file
        }
        
        # --- 3c. Extract preview frame with FFmpeg ---
        Write-Host "  -> Extracting preview frame..."
        try {
            $ffmpegArgsPreview = "-i `"$lqPath`" -ss 00:00:01 -vframes 1 `"$previewPath`""
            & $ffmpegPath $ffmpegArgsPreview 2>&1 | Out-Null # Redirect stderr to null
            Write-Host "  -> Preview extraction successful."
        } catch {
            Write-Error "  -> Failed to extract preview for '$($rawFile.Name)': ${Error.Exception.Message}"
            continue # Skip to next raw file
        }
        
        # --- 3d. Delete the original raw file ---
        Write-Host "  -> Removing original from 'raw' folder."
        try {
            Remove-Item -Path $rawFile.FullName -ErrorAction Stop
            Write-Host "  -> Raw file removed."
        } catch {
            Write-Error "  -> Failed to remove raw file '$($rawFile.Name)': ${Error.Exception.Message}"
            # Not a critical error, just log and continue
        }
    }
}

# --- 4. Heal existing videos (create missing LQ/previews) ---
Write-Host "--- Checking and healing existing processed videos ---"
$hqFilesAlreadyProcessed = @(Get-ChildItem -Path $vidHQDir -Filter "*.mp4" -ErrorAction SilentlyContinue)
foreach ($hqFile in $hqFilesAlreadyProcessed) {
    $videoName = $hqFile.BaseName
    $lqCorrespondingPath = Join-Path $vidLQDir "$videoName.mp4"
    $previewCorrespondingPath = Join-Path $previewsDir "$videoName.jpg"
    
    $healed = $false

    # Check and create missing LQ video
    if (-not (Test-Path $lqCorrespondingPath)) {
        Write-Host "  -> Missing LQ for $($hqFile.Name). Creating..."
        try {
            $ffmpegArgsLQ = "-i `"$($hqFile.FullName)`" -vf `"scale=${lqResolution}:-1`" -c:v libx264 -preset veryfast -crf $lqCrf `"$lqCorrespondingPath`""
            & $ffmpegPath $ffmpegArgsLQ 2>&1 | Out-Null
            Write-Host "  -> LQ created for $($hqFile.Name)."
            $healed = $true
        } catch {
            Write-Error "  -> Failed to create LQ for '$($hqFile.Name)': ${Error.Exception.Message}"
        }
    }

    # Check and create missing preview
    if (-not (Test-Path $previewCorrespondingPath)) {
        Write-Host "  -> Missing Preview for $($hqFile.Name). Creating..."
        try {
            # Use LQ if available, else HQ for preview generation
            $sourceForPreview = if (Test-Path $lqCorrespondingPath) { $lqCorrespondingPath } else { $hqFile.FullName }
            $ffmpegArgsPreview = "-i `"$sourceForPreview`" -ss 00:00:01 -vframes 1 `"$previewCorrespondingPath`""
            & $ffmpegPath $ffmpegArgsPreview 2>&1 | Out-Null
            Write-Host "  -> Preview created for $($hqFile.Name)."
            $healed = $true
        } catch {
            Write-Error "  -> Failed to create preview for '$($hqFile.Name)': ${Error.Exception.Message}"
        }
    }
    if ($healed) { $newFilesAdded = $true } # Mark that something was added/changed for Git
}


# --- 5. Commit and Push to GitHub ---
if ($newFilesAdded -or (git -C $baseDir status --porcelain | Select-String -Pattern "^(A|M|D|\?\?)\s+(vidHQ/|vidLQ/|previews/)").Length -gt 0) {
    Write-Host "Committing and pushing changes to GitHub..."
    try {
        # Stage all changes in the entire repository (new, modified, deleted files)
        git -C $baseDir add -A
        if ($LASTEXITCODE -ne 0) { throw "Git add failed with exit code $LASTEXITCODE" }
        Write-Host "  -> Git add successful."
        
        git -C $baseDir commit -m "$commitMessage"
        if ($LASTEXITCODE -ne 0) { throw "Git commit failed with exit code $LASTEXITCODE" }
        Write-Host "  -> Git commit successful."
        
        git -C $baseDir push
        if ($LASTEXITCODE -ne 0) { throw "Git push failed with exit code $LASTEXITCODE" }
        Write-Host "  -> Git push successful."

        Write-Host "Done. Videos processed and pushed."
    } catch {
        Write-Error "Failed to commit or push to Git: ${Error.Exception.Message}"
        Write-Warning "Local changes might still be staged or committed. Please resolve manually."
    }
} else {
    Write-Host "No new files were processed or detected as needing a push."
}

Write-Host "Script finished."