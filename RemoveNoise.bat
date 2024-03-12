@echo off
setlocal enabledelayedexpansion

:: Declare paths for FFmpeg and RNNoise, and define necessary audio format variables
SET "ffmpeg=your-directory-to-ffmpeg/ffmpeg.exe"
SET "rnnoise=your-directory-to-cloned-repository/Audio-Enhancer-RNN/rnnoise_windows/examples/rnnoise_demo.exe"
SET "pcm=pcm_s16le"
SET "sample_rate=48000"
SET "format=s16le"

:: Verify an input file has been provided
if "%~1"=="" (
    echo Usage: %0 ^<input_file^>
    exit /b 1
)

set "INPUT_FILE=%~1"

:: Verify the input file exists
if not exist "!INPUT_FILE!" (
    echo Input file does not exist.
    exit /b 1
)

:: Extract the file extension and file name without extension
for %%I in ("!INPUT_FILE!") do (
    set "EXTENSION=%%~xI"
    set "FILE_NAME=%%~nI"
)

:: Prepare WAV file and processed output file names
set "WAV_FILE=!FILE_NAME!.wav"
set "FINAL_OUTPUT=!FILE_NAME!_denoised!EXTENSION!"

:: Convert input to WAV format if not already in WAV, targeting mono or stereo as needed
echo Converting input file to WAV format...
%ffmpeg% -i "!INPUT_FILE!" -acodec %pcm% -ar %sample_rate% -ac 1 "!WAV_FILE!"

:: Redirect FFmpeg's output to a temporary file
%ffmpeg% -i "!WAV_FILE!" 2>ffmpeg_output.txt

:: Check the temporary file for 'stereo' keyword
findstr /i "stereo" ffmpeg_output.txt >nul && set "STEREO=1" || set "STEREO=0"

:: Echo the STEREO variable for debugging
echo Stereo: !STEREO!


:: Process mono file
if !STEREO! equ 0 (
    echo Processing mono file...
    SET "PCM_FILE=!FILE_NAME!_mono.pcm"
    SET "PCM_DENOISED=!FILE_NAME!_mono_denoised.pcm"

    %ffmpeg% -i "!WAV_FILE!" -f %format% -acodec %pcm% -ac 1 -ar %sample_rate% "!PCM_FILE!"
    %rnnoise% "!PCM_FILE!" "!PCM_DENOISED!"

    :: Convert denoised PCM back to the original format
    %ffmpeg% -f %format% -ar %sample_rate% -ac 1 -i "!PCM_DENOISED!" "!FINAL_OUTPUT!"
) else (
    echo Processing stereo file...
    :: Split the stereo file into two mono files
    SET "LEFT_CHANNEL=!FILE_NAME!_left.pcm"
    SET "RIGHT_CHANNEL=!FILE_NAME!_right.pcm"
    SET "LEFT_DENOISED=!FILE_NAME!_left_denoised.pcm"
    SET "RIGHT_DENOISED=!FILE_NAME!_right_denoised.pcm"

    %ffmpeg% -i "!WAV_FILE!" -map_channel 0.0.0 -f %format% -acodec %pcm% -ac 1 -ar 48000 "!LEFT_CHANNEL!"
    %ffmpeg% -i "!WAV_FILE!" -map_channel 0.0.1 -f %format% -acodec %pcm% -ac 1 -ar 48000 "!RIGHT_CHANNEL!"

    :: Apply RNNoise to each channel
    %rnnoise% "!LEFT_CHANNEL!" "!LEFT_DENOISED!"
    %rnnoise% "!RIGHT_CHANNEL!" "!RIGHT_DENOISED!"

    :: Combine the denoised left and right channels into a stereo audio file
    %ffmpeg% -f %format% -ar %sample_rate% -ac 1 -i "!LEFT_DENOISED!" -f %format% -ar %sample_rate% -ac 1 -i "!RIGHT_DENOISED!" -filter_complex "[0:a][1:a]amerge=inputs=2[a]" -map "[a]" -ac 2 "!FINAL_OUTPUT!"
)

:: Cleanup
echo Cleaning up temporary files...
if exist "!WAV_FILE!" del "!WAV_FILE!"
if exist "!PCM_FILE!" del "!PCM_FILE!"
if exist "!PCM_DENOISED!" del "!PCM_DENOISED!"
if exist "!LEFT_CHANNEL!" del "!LEFT_CHANNEL!"
if exist "!RIGHT_CHANNEL!" del "!RIGHT_CHANNEL!"
if exist "!LEFT_DENOISED!" del "!LEFT_DENOISED!"
if exist "!RIGHT_DENOISED!" del "!RIGHT_DENOISED!"

echo Processing completed successfully.
endlocal
