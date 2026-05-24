@echo off
setlocal enabledelayedexpansion

REM ============================================================================
REM Hermes Agent - Portable Launcher (Windows)
REM ============================================================================
REM Double-click this file to launch Hermes.
REM On first run, it downloads ~600MB of runtime files automatically.
REM All data stays in the "data\" folder - nothing touches the host computer.
REM ============================================================================

REM Resolve portable root (directory containing this script)
set "PORTABLE_ROOT=%~dp0"
set "PORTABLE_ROOT=%PORTABLE_ROOT:~0,-1%"

set "HERMES_HOME=%PORTABLE_ROOT%\data"
set "CACHE_DIR=%PORTABLE_ROOT%\.cache"
set "RUNTIME_DIR=%CACHE_DIR%\runtimes\windows-x64"
set "SRC_DIR=%PORTABLE_ROOT%\src"

REM ---------------------------------------------------------------------------
REM First-run setup
REM ---------------------------------------------------------------------------
if not exist "%RUNTIME_DIR%\ready.flag" (
    echo.
    echo ============================================
    echo    Hermes Portable - First Run Setup
    echo ============================================
    echo  This will download ~600MB of runtime files
    echo  for Windows x64. Please be patient.
    echo ============================================
    echo.
    powershell -ExecutionPolicy Bypass -File "%PORTABLE_ROOT%\scripts\setup-windows.ps1" -Root "%PORTABLE_ROOT%"
    if errorlevel 1 (
        echo.
        echo [ERROR] Setup failed. Please check your internet connection and try again.
        pause
        exit /b 1
    )
)

REM ---------------------------------------------------------------------------
REM Environment isolation - keep everything inside the portable folder
REM ---------------------------------------------------------------------------
set "VIRTUAL_ENV=%RUNTIME_DIR%\venv"
set "PATH=%VIRTUAL_ENV%\Scripts;%RUNTIME_DIR%\python;%RUNTIME_DIR%\python\Scripts;%RUNTIME_DIR%\node;%RUNTIME_DIR%\uv;%RUNTIME_DIR%\bin;%PATH%"
set "PYTHONNOUSERSITE=1"
set "PYTHONHOME="
set "PYTHONPATH="
set "UV_NO_CONFIG=1"
set "UV_PYTHON=%RUNTIME_DIR%\python\python.exe"
set "PLAYWRIGHT_BROWSERS_PATH=%RUNTIME_DIR%\playwright"
set "NODE_PATH=%RUNTIME_DIR%\node\node_modules"
set "NPM_CONFIG_PREFIX=%RUNTIME_DIR%\node"

REM Prevent Node from writing to host appdata
set "APPDATA=%PORTABLE_ROOT%\.cache\windows-appdata"
set "LOCALAPPDATA=%PORTABLE_ROOT%\.cache\windows-localappdata"

REM Portable Ollama isolation - keep all downloaded GGUF models on the USB drive
set "OLLAMA_MODELS=%HERMES_HOME%\models"


REM ---------------------------------------------------------------------------
REM Launch Hermes
REM ---------------------------------------------------------------------------
if not exist "%SRC_DIR%\hermes-agent" (
    echo [ERROR] Hermes source not found. Please delete .cache and try again.
    pause
    exit /b 1
)

cd /d "%SRC_DIR%\hermes-agent"

REM Strip "hermes" from the start of arguments if user typed "launch.bat hermes setup"
set "ARGS=%*"
if /I "%~1"=="hermes" (
    set "ARGS=%ARGS:~7%"
)

REM If explicit arguments were passed, run Hermes directly (skip menu)
if not "%ARGS%"=="" (
    hermes %ARGS%
    exit /b
)

REM ---------------------------------------------------------------------------
REM ANSI Color Setup
REM ---------------------------------------------------------------------------
for /f %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"
set "RESET=%ESC%[0m"
set "BOLD=%ESC%[1m"
set "DIM=%ESC%[2m"
set "CYAN=%ESC%[36m"
set "BRIGHT_CYAN=%ESC%[96m"
set "GREEN=%ESC%[32m"
set "BRIGHT_GREEN=%ESC%[92m"
set "YELLOW=%ESC%[33m"
set "BRIGHT_YELLOW=%ESC%[93m"
set "RED=%ESC%[31m"
set "BRIGHT_RED=%ESC%[91m"
set "WHITE=%ESC%[37m"
set "BRIGHT_WHITE=%ESC%[97m"
set "GRAY=%ESC%[90m"
set "BG_CYAN=%ESC%[46m%ESC%[30m"
set "BG_DARK=%ESC%[40m%ESC%[37m"

REM ---------------------------------------------------------------------------
REM Status Detection
REM ---------------------------------------------------------------------------
:detect_status
set "SETUP_STATUS=Not configured"
set "SETUP_ICON=[x]"
set "SETUP_COLOR=%RED%"
set "PROVIDER_NAME="
set "MODEL_NAME="
if exist "%HERMES_HOME%\.env" (
    findstr /R /C:"^[A-Z].*=" "%HERMES_HOME%\.env" >nul 2>&1
    if not errorlevel 1 (
        set "SETUP_STATUS=Configured"
        set "SETUP_ICON=[OK]"
        set "SETUP_COLOR=%BRIGHT_GREEN%"
    )
)

if exist "%HERMES_HOME%\config.yaml" (
    for /f "usebackq tokens=2 delims=: " %%a in (`findstr /R /C:"^  provider:" "%HERMES_HOME%\config.yaml"`) do (
        if not defined PROVIDER_NAME set "PROVIDER_NAME=%%a"
    )
    for /f "usebackq tokens=2 delims=: " %%a in (`findstr /R /C:"^  default:" "%HERMES_HOME%\config.yaml"`) do (
        if not defined MODEL_NAME set "MODEL_NAME=%%a"
    )
)

set "GATEWAY_STATUS=Stopped"
set "GATEWAY_ICON=[ ]"
set "GATEWAY_COLOR=%GRAY%"
set "GATEWAY_PID="
if exist "%HERMES_HOME%\gateway.pid" (
    for /f "usebackq tokens=2 delims=:," %%a in (`findstr /R /C:"\"pid\"" "%HERMES_HOME%\gateway.pid"`) do (
        set "raw=%%a"
        set "GATEWAY_PID=!raw: =!"
    )
)
if defined GATEWAY_PID (
    tasklist /FI "PID eq !GATEWAY_PID!" 2>nul | findstr /I "!GATEWAY_PID!" >nul
    if not errorlevel 1 (
        set "GATEWAY_STATUS=Running (PID !GATEWAY_PID!)"
        set "GATEWAY_ICON=[OK]"
        set "GATEWAY_COLOR=%BRIGHT_GREEN%"
    ) else (
        set "GATEWAY_STATUS=Stopped (stale lock)"
        set "GATEWAY_ICON=[!]"
        set "GATEWAY_COLOR=%YELLOW%"
    )
)

set "HERMES_VERSION=unknown"
if exist "%SRC_DIR%\hermes-agent\hermes_cli\__init__.py" (
    for /f "usebackq tokens=3" %%a in (`findstr /R /C:"__version__" "%SRC_DIR%\hermes-agent\hermes_cli\__init__.py"`) do (
        set "rawver=%%a"
        set "HERMES_VERSION=!rawver:"=!"
    )
)

REM ---------------------------------------------------------------------------
REM Main Menu
REM ---------------------------------------------------------------------------
:show_menu
echo.
echo.
echo %BRIGHT_CYAN%----------------------------------------------------------------%RESET%
echo %BOLD%%BRIGHT_WHITE%                    HERMES PORTABLE LAUNCHER%RESET%
echo %DIM%%GRAY%                         AI Agent for Everyone%RESET%
echo %BRIGHT_CYAN%----------------------------------------------------------------%RESET%
echo.
echo  %DIM%Setup%RESET%    !SETUP_COLOR!!SETUP_ICON!%RESET% %WHITE%!SETUP_STATUS!%RESET%
if defined PROVIDER_NAME echo  %DIM%Provider%RESET% %CYAN%!PROVIDER_NAME!%RESET%
if defined MODEL_NAME echo  %DIM%Model%RESET%    %WHITE%!MODEL_NAME!%RESET%
echo  %DIM%Gateway%RESET%  !GATEWAY_COLOR!!GATEWAY_ICON!%RESET% %WHITE%!GATEWAY_STATUS!%RESET%
echo  %DIM%Version%RESET%  %GRAY%v!HERMES_VERSION!%RESET%
echo.
echo %BRIGHT_CYAN%----------------------------------------------------------------%RESET%
echo.
echo  %BRIGHT_YELLOW%[1]%RESET%  %WHITE%Start Hermes Chat (TUI)%RESET%
echo  %BRIGHT_YELLOW%[2]%RESET%  %WHITE%Start Web Dashboard (GUI)%RESET%
echo  %BRIGHT_YELLOW%[3]%RESET%  %WHITE%Setup / Reconfigure Hermes%RESET%
if "!GATEWAY_STATUS!"=="Running (PID !GATEWAY_PID!)" (
    echo  %BRIGHT_YELLOW%[4]%RESET%  %WHITE%Stop Gateway%RESET%  %RED%[live]%RESET%
) else (
    echo  %BRIGHT_YELLOW%[4]%RESET%  %WHITE%Start Gateway%RESET%
)
echo  %BRIGHT_YELLOW%[5]%RESET%  %WHITE%Advanced Options%RESET%  %GRAY%--^>%RESET%
echo  %BRIGHT_YELLOW%[6]%RESET%  %GRAY%Exit%RESET%
echo.
echo %BRIGHT_CYAN%----------------------------------------------------------------%RESET%
echo.

echo %BRIGHT_CYAN%Select option:%RESET% & choice /C 123456 /N
if errorlevel 6 goto :menu_exit
if errorlevel 5 goto :show_advanced
if errorlevel 4 goto :menu_gateway
if errorlevel 3 goto :menu_setup
if errorlevel 2 goto :menu_dashboard
if errorlevel 1 goto :menu_chat
goto :show_menu

:menu_dashboard
echo.
echo %CYAN%Starting premium Web Dashboard...%RESET%
echo %GRAY%(Vite/React frontend is fully optimized for mobile, tablet, and laptop)%RESET%
echo.
call :check_ollama
if errorlevel 1 goto :show_menu
hermes dashboard
goto :show_menu


REM ---------------------------------------------------------------------------
REM Menu Actions
REM ---------------------------------------------------------------------------
:menu_chat
echo.
call :check_ollama
if errorlevel 1 goto :show_menu

set "LLAMAFILE_RUNNING=0"
set "LLAMAFILE_EXE=%HERMES_HOME%\bin\llamafile.exe"
set "LOCAL_SERVE=0"

if exist "%HERMES_HOME%\config.yaml" (
    findstr /C:"provider: custom" "%HERMES_HOME%\config.yaml" >nul 2>&1
    if not errorlevel 1 (
        findstr /C:"base_url: http://127.0.0.1:8080" "%HERMES_HOME%\config.yaml" >nul 2>&1
        if not errorlevel 1 (
            if exist "!LLAMAFILE_EXE!" (
                set "LOCAL_SERVE=1"
            )
        )
    )
)

if "!LOCAL_SERVE!"=="1" (
    set "MODEL_PATH="
    for %%f in ("%HERMES_HOME%\models\*.gguf") do (
        if not defined MODEL_PATH set "MODEL_PATH=%%f"
    )
    if defined MODEL_PATH (
        echo %CYAN%Starting local llamafile server with model: !MODEL_PATH!%RESET%
        start /B "llamafile" "!LLAMAFILE_EXE!" --server --host 127.0.0.1 --port 8080 --model "!MODEL_PATH!" --nobrowser >nul 2>&1
        set "LLAMAFILE_RUNNING=1"
        timeout /t 3 /nobreak >nul
    ) else (
        echo %YELLOW%[WARN] Llamafile executable found, but no .gguf models found in data\models\%RESET%
    )
)

hermes

if "!LLAMAFILE_RUNNING!"=="1" (
    echo %CYAN%Stopping local llamafile server ...%RESET%
    taskkill /f /fi "IMAGENAME eq llamafile.exe" >nul 2>&1
)
goto :show_menu

:check_ollama
set "OLLAMA_OFFLINE=0"
if not exist "%HERMES_HOME%\config.yaml" exit /b 0

findstr /C:"base_url: http://127.0.0.1:11434" "%HERMES_HOME%\config.yaml" >nul 2>&1
if errorlevel 1 exit /b 0

echo Checking if local Ollama server is running on port 11434...
powershell -Command "try { $t = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 11434); if ($t.Connected) { exit 0 } } catch { exit 1 }" >nul 2>&1
if not errorlevel 1 exit /b 0

set "OLLAMA_OFFLINE=1"
echo %YELLOW%[WARN] Local Ollama server is not running on port 11434!%RESET%
echo Please make sure Ollama is started on the host system,
echo and that you have pulled the model by running:
echo   ollama pull qwen2.5-coder:1.5b
echo.
set "CONFIRM="
set /p "CONFIRM=Do you want to continue anyway? [y/N]: "
if /I not "!CONFIRM!"=="y" (
    exit /b 1
)
exit /b 0

:menu_setup
echo.
echo %BRIGHT_CYAN%----------------------------------------------------------------%RESET%
echo %BOLD%%BRIGHT_WHITE%                  Hermes Setup Configuration%RESET%
echo %BRIGHT_CYAN%----------------------------------------------------------------%RESET%
echo  Choose how you want to run Hermes:
echo.
echo  %BRIGHT_YELLOW%[1]%RESET%  %WHITE%Local Ollama Server (Recommended - GPU Accelerated)%RESET%
echo  %BRIGHT_YELLOW%[2]%RESET%  %WHITE%Local USB Model (Offline - CPU served from USB)%RESET%
echo  %BRIGHT_YELLOW%[3]%RESET%  %WHITE%Online Providers (Cloud APIs: OpenRouter, DeepSeek, etc.)%RESET%
echo  %BRIGHT_YELLOW%[4]%RESET%  %GRAY%Back to Main Menu%RESET%
echo %BRIGHT_CYAN%----------------------------------------------------------------%RESET%
echo.
echo %BRIGHT_CYAN%Select option:%RESET% & choice /C 1234 /N
if errorlevel 4 goto :show_menu
if errorlevel 3 goto :setup_online
if errorlevel 2 goto :setup_usb_local
if errorlevel 1 goto :setup_ollama_local
goto :menu_setup

:setup_online
echo.
hermes setup
goto :detect_status

:setup_ollama_local
echo.
set "OLLAMA_EXE=%HERMES_HOME%\bin\ollama\ollama.exe"
set "PORTABLE_OLLAMA_EXISTS=1"
if not exist "!OLLAMA_EXE!" (
    set "PORTABLE_OLLAMA_EXISTS=0"
    if exist "%LOCALAPPDATA%\Programs\Ollama\ollama.exe" (
        set "OLLAMA_EXE=%LOCALAPPDATA%\Programs\Ollama\ollama.exe"
    ) else (
        where.exe ollama >nul 2>&1
        if not errorlevel 1 (
            set "OLLAMA_EXE=ollama"
        )
    )
)

:: Check if Ollama executable actually exists or is accessible
if exist "!OLLAMA_EXE!" goto :ollama_executable_ready
where.exe "!OLLAMA_EXE!" >nul 2>&1
if not errorlevel 1 goto :ollama_executable_ready

:: Download portable Ollama if not found
echo.
echo %YELLOW%[INFO] Local Ollama CLI was not found on your system.%RESET%
echo We can automatically download and set up a 100%% PORTABLE Ollama server
echo directly inside your USB drive (~170 MB). All GGUF models and data will be
echo saved on the USB drive, keeping your host computer completely clean!
echo.
set "CONFIRM="
set /p "CONFIRM=Do you want to download portable Ollama now? [y/N]: "
if /I not "!CONFIRM!"=="y" (
    echo Setup cancelled. Returning to setup menu.
    pause
    goto :menu_setup
)

powershell -ExecutionPolicy Bypass -File "%PORTABLE_ROOT%\scripts\download_helper.ps1" -Url "https://ollama.com/download/ollama-windows-amd64.zip" -OutFile "%HERMES_HOME%\bin\ollama-windows-amd64.zip" -ExtractDir "%HERMES_HOME%\bin\ollama"
     
if errorlevel 1 (
    echo.
    echo %RED%[ERROR] Download or extraction failed. Please check internet connection.%RESET%
    pause
    goto :menu_setup
)

if not exist "%HERMES_HOME%\bin\ollama\ollama.exe" (
    echo.
    echo %RED%[ERROR] Portable Ollama executable was not found. Download or extraction failed.%RESET%
    pause
    goto :menu_setup
)

echo %GREEN%✓ Portable Ollama successfully installed!%RESET%
set "OLLAMA_EXE=%HERMES_HOME%\bin\ollama\ollama.exe"
set "PORTABLE_OLLAMA_EXISTS=1"

:ollama_executable_ready

echo Checking if local Ollama server is running on port 11434...
powershell -Command "try { $t = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 11434); if ($t.Connected) { exit 0 } } catch { exit 1 }" >nul 2>&1
if not errorlevel 1 goto :ollama_running

echo %YELLOW%Ollama is not running. Attempting to start local Ollama server...%RESET%
if "!PORTABLE_OLLAMA_EXISTS!"=="1" (
    echo Starting portable Ollama via CLI serve...
    start /B "ollama-serve" "!OLLAMA_EXE!" serve >nul 2>&1
) else (
    if exist "%LOCALAPPDATA%\Programs\Ollama\ollama app.exe" (
        echo Starting Ollama application...
        start "" "%LOCALAPPDATA%\Programs\Ollama\ollama app.exe"
    ) else (
        echo Ollama app not found in LocalAppData. Starting via CLI serve...
        start /B "ollama-serve" "!OLLAMA_EXE!" serve >nul 2>&1
    )
)
echo Waiting 5 seconds for server startup...
timeout /t 5 /nobreak >nul

powershell -Command "try { $t = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 11434); if ($t.Connected) { exit 0 } } catch { exit 1 }" >nul 2>&1
if errorlevel 1 (
    echo.
    echo %RED%[ERROR] Could not start or connect to Ollama server. Please verify it is installed and running.%RESET%
    pause
    goto :menu_setup
)
echo %GREEN%✓ Ollama server successfully started!%RESET%
goto :ollama_running_check_done

:ollama_running
echo %GREEN%✓ Local Ollama server is already running!%RESET%

:ollama_running_check_done

set "RECS="
for /f "delims=" %%i in ('python scripts/detect_system.py --recommend-tags') do set "RECS=%%i"

set "M1_LABEL=Qwen 2.5 Coder 1.5B   (qwen2.5-coder:1.5b)"
set "M2_LABEL=Qwen 2.5 Coder 7B      (qwen2.5-coder:7b)"
set "M3_LABEL=Gemma 4 E2B             (gemma4:e2b)"
set "M4_LABEL=Gemma 4 E4B             (gemma4:e4b)"
set "M5_LABEL=DeepSeek-Coder 1.3B     (deepseek-coder:1.3b)"
set "M6_LABEL=DeepSeek-Coder 6.7B     (deepseek-coder:6.7b)"

echo !RECS! | findstr /C:"qwen2.5-coder:1.5b" >nul 2>&1
if not errorlevel 1 set "M1_LABEL=!M1_LABEL! %GREEN%(Recommended)%RESET%"

echo !RECS! | findstr /C:"qwen2.5-coder:7b" >nul 2>&1
if not errorlevel 1 set "M2_LABEL=!M2_LABEL! %GREEN%(Recommended)%RESET%"

echo !RECS! | findstr /C:"gemma4:e2b" >nul 2>&1
if not errorlevel 1 set "M3_LABEL=!M3_LABEL! %GREEN%(Recommended)%RESET%"

echo !RECS! | findstr /C:"gemma4:e4b" >nul 2>&1
if not errorlevel 1 set "M4_LABEL=!M4_LABEL! %GREEN%(Recommended)%RESET%"

echo !RECS! | findstr /C:"deepseek-coder:1.3b" >nul 2>&1
if not errorlevel 1 set "M5_LABEL=!M5_LABEL! %GREEN%(Recommended)%RESET%"

echo !RECS! | findstr /C:"deepseek-coder:6.7b" >nul 2>&1
if not errorlevel 1 set "M6_LABEL=!M6_LABEL! %GREEN%(Recommended)%RESET%"

:menu_select_model
echo.
echo %BRIGHT_CYAN%----------------------------------------------------------------%RESET%
echo %BOLD%%BRIGHT_WHITE%                  Select Local Ollama Model%RESET%
echo %BRIGHT_CYAN%----------------------------------------------------------------%RESET%
echo  Select the model you wish to use. Recommended models are highlighted.
echo.
echo  %BRIGHT_YELLOW%[1]%RESET%  !M1_LABEL!
echo  %BRIGHT_YELLOW%[2]%RESET%  !M2_LABEL!
echo  %BRIGHT_YELLOW%[3]%RESET%  !M3_LABEL!
echo  %BRIGHT_YELLOW%[4]%RESET%  !M4_LABEL!
echo  %BRIGHT_YELLOW%[5]%RESET%  !M5_LABEL!
echo  %BRIGHT_YELLOW%[6]%RESET%  !M6_LABEL!
echo  %BRIGHT_YELLOW%[7]%RESET%  %GRAY%Cancel setup (Back to menu)%RESET%
echo %BRIGHT_CYAN%----------------------------------------------------------------%RESET%
echo.
echo %BRIGHT_CYAN%Select option:%RESET% & choice /C 1234567 /N

if errorlevel 7 goto :menu_setup
if errorlevel 6 set "MODEL_TAG=deepseek-coder:6.7b" & goto :pull_and_configure
if errorlevel 5 set "MODEL_TAG=deepseek-coder:1.3b" & goto :pull_and_configure
if errorlevel 4 set "MODEL_TAG=gemma4:e4b"          & goto :pull_and_configure
if errorlevel 3 set "MODEL_TAG=gemma4:e2b"          & goto :pull_and_configure
if errorlevel 2 set "MODEL_TAG=qwen2.5-coder:7b"     & goto :pull_and_configure
if errorlevel 1 set "MODEL_TAG=qwen2.5-coder:1.5b"   & goto :pull_and_configure
goto :menu_select_model

:pull_and_configure
echo.
echo %CYAN%Pulling local model: !MODEL_TAG!...%RESET%
echo Running: "!OLLAMA_EXE!" pull !MODEL_TAG!
"!OLLAMA_EXE!" pull !MODEL_TAG!
if errorlevel 1 (
    echo.
    echo %RED%[ERROR] Failed to pull model '!MODEL_TAG!'. Please check internet connection.%RESET%
    pause
    goto :menu_select_model
)
echo %GREEN%✓ Model successfully pulled!%RESET%
echo.
echo %CYAN%Configuring Hermes to use local Ollama model "!MODEL_TAG!"...%RESET%
hermes config set model.provider custom
hermes config set model.base_url http://127.0.0.1:11434/v1
hermes config set model.default !MODEL_TAG!
echo %GREEN%✓ Configuration updated successfully!%RESET%
pause
goto :detect_status

:setup_usb_local
echo.
set "LLAMAFILE_EXE=%HERMES_HOME%\bin\llamafile.exe"
set "MODEL_FILE=%HERMES_HOME%\models\qwen2.5-coder-1.5b-instruct-q4_k_m.gguf"
set "DOWNLOAD_REQUIRED=0"

if not exist "!LLAMAFILE_EXE!" set "DOWNLOAD_REQUIRED=1"
if not exist "!MODEL_FILE!" set "DOWNLOAD_REQUIRED=1"

if not "!DOWNLOAD_REQUIRED!"=="1" goto :usb_local_config_only

echo %YELLOW%[INFO] Local model assets are missing from the USB drive.%RESET%
echo This setup requires downloading:
echo  - Llamafile runner (~35 MB)
echo  - Qwen2.5-Coder-1.5B model (~1.0 GB)
echo.
set "CONFIRM="
set /p "CONFIRM=Do you want to download these files now? [y/N]: "
if /I not "!CONFIRM!"=="y" (
    echo Setup cancelled. Returning to setup menu.
    pause
    goto :menu_setup
)

powershell -ExecutionPolicy Bypass -File "%PORTABLE_ROOT%\scripts\download_helper.ps1" -Url "https://github.com/mozilla-ai/llamafile/releases/download/0.10.1/llamafile-0.10.1" -OutFile "!LLAMAFILE_EXE!"
powershell -ExecutionPolicy Bypass -File "%PORTABLE_ROOT%\scripts\download_helper.ps1" -Url "https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf" -OutFile "!MODEL_FILE!"
     
if errorlevel 1 (
    echo.
    echo %RED%[ERROR] Download failed. Please check your internet connection.%RESET%
    pause
    goto :menu_setup
)

if not exist "!LLAMAFILE_EXE!" (
    echo.
    echo %RED%[ERROR] Llamafile executable was not found. Download failed.%RESET%
    pause
    goto :menu_setup
)
if not exist "!MODEL_FILE!" (
    echo.
    echo %RED%[ERROR] Model GGUF file was not found. Download failed.%RESET%
    pause
    goto :menu_setup
)

echo %GREEN%✓ Download completed successfully!%RESET%

:usb_local_config_only
echo.
echo %CYAN%Configuring Hermes to use local USB model...%RESET%
hermes config set model.provider custom
hermes config set model.base_url http://127.0.0.1:8080/v1
hermes config set model.default qwen2.5-coder-1.5b-instruct-q4_k_m.gguf
echo %GREEN%✓ Configuration updated!%RESET%
pause
goto :detect_status

:menu_gateway
if "!GATEWAY_STATUS!"=="Running (PID !GATEWAY_PID!)" (
    hermes gateway stop
    echo.
    echo %BRIGHT_GREEN%Gateway stopped.%RESET%
) else (
    echo.
    echo %CYAN%Starting gateway in background ...%RESET%
    start "" hermes gateway
    timeout /t 2 /nobreak >nul
)
pause
goto :detect_status

:menu_exit
echo.
echo.
echo %GRAY%Goodbye!%RESET%
echo.
exit /b

REM ---------------------------------------------------------------------------
REM Advanced Menu
REM ---------------------------------------------------------------------------
:show_advanced
echo.
echo.
echo %BRIGHT_CYAN%----------------------------------------------------------------%RESET%
echo %BOLD%%BRIGHT_WHITE%                       Advanced Options%RESET%
echo %BRIGHT_CYAN%----------------------------------------------------------------%RESET%
echo.
echo  %BRIGHT_YELLOW%[1]%RESET%  %WHITE%Run Doctor%RESET%            %GRAY%- check for issues%RESET%
echo  %BRIGHT_YELLOW%[2]%RESET%  %WHITE%View Logs%RESET%             %GRAY%- last 20 lines%RESET%
echo  %BRIGHT_YELLOW%[3]%RESET%  %WHITE%Edit Config%RESET%           %GRAY%- open in editor%RESET%
echo  %BRIGHT_YELLOW%[4]%RESET%  %WHITE%Restart Gateway%RESET%       %GRAY%- stop + start%RESET%
echo  %BRIGHT_YELLOW%[5]%RESET%  %WHITE%Update Hermes%RESET%         %GRAY%- fetch latest%RESET%
echo  %BRIGHT_YELLOW%[6]%RESET%  %GRAY%Back to Main Menu%RESET%
echo.
echo %BRIGHT_CYAN%----------------------------------------------------------------%RESET%
echo.

echo %BRIGHT_CYAN%Select option:%RESET% & choice /C 123456 /N
if errorlevel 6 goto :show_menu
if errorlevel 5 goto :adv_update
if errorlevel 4 goto :adv_restart
if errorlevel 3 goto :adv_config
if errorlevel 2 goto :adv_logs
if errorlevel 1 goto :adv_doctor
goto :show_advanced

:adv_doctor
echo.
hermes doctor
pause
goto :show_advanced

:adv_logs
echo.
if exist "%HERMES_HOME%\logs\gateway.log" (
    echo %CYAN%=== Gateway Log (last 20 lines) ===%RESET%
    powershell -Command "Get-Content '%HERMES_HOME%\logs\gateway.log' -Tail 20"
) else (
    echo %YELLOW%No logs found.%RESET%
)
echo.
pause
goto :show_advanced

:adv_config
echo.
hermes config edit
goto :show_advanced

:adv_restart
hermes gateway restart
echo.
echo %BRIGHT_GREEN%Gateway restarted.%RESET%
pause
goto :detect_status

:adv_update
echo.
hermes update
pause
goto :show_advanced
