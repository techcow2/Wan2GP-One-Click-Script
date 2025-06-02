@echo off
setlocal enabledelayedexpansion

:: Wan2GP One-Click Installer and Launcher for Windows
:: This script automatically installs and runs Wan2GP with all dependencies

title Wan2GP Auto-Installer and Launcher

echo ========================================
echo    Wan2GP One-Click Installer
echo ========================================
echo.

:: Check if already installed
if exist "Wan2GP\wan2gp_installed.flag" (
    echo Installation detected. Launching Wan2GP...
    goto :launch
)

echo Starting fresh installation...
echo.

:: Create installation directory
if not exist "Wan2GP" mkdir Wan2GP
cd Wan2GP

:: Check for Python 3.10
echo [1/8] Checking Python 3.10 installation...
python --version 2>nul | findstr "3.10" >nul
if errorlevel 1 (
    echo Python 3.10 not found. Installing Python 3.10.9...
    
    :: Download Python 3.10.9
    echo Downloading Python 3.10.9...
    powershell -Command "& {Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.10.9/python-3.10.9-amd64.exe' -OutFile 'python-installer.exe'}"
    
    :: Install Python silently
    echo Installing Python 3.10.9...
    python-installer.exe /quiet InstallAllUsers=0 PrependPath=1 Include_test=0
    
    :: Wait for installation to complete
    timeout /t 30 /nobreak >nul
    
    :: Refresh environment variables
    call refreshenv.cmd 2>nul || (
        echo Please restart this script after Python installation completes.
        pause
        exit /b 1
    )
    
    del python-installer.exe
) else (
    echo Python 3.10 found!
)

:: Check for Git
echo [2/8] Checking Git installation...
git --version 2>nul >nul
if errorlevel 1 (
    echo Git not found. Installing Git...
    
    :: Download Git
    echo Downloading Git...
    powershell -Command "& {Invoke-WebRequest -Uri 'https://github.com/git-for-windows/git/releases/download/v2.42.0.windows.2/Git-2.42.0.2-64-bit.exe' -OutFile 'git-installer.exe'}"
    
    :: Install Git silently
    echo Installing Git...
    git-installer.exe /VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS="icons,ext\reg\shellhere,assoc,assoc_sh"
    
    :: Wait for installation
    timeout /t 60 /nobreak >nul
    
    :: Add Git to PATH for current session
    set "PATH=%PATH%;C:\Program Files\Git\bin"
    
    del git-installer.exe
) else (
    echo Git found!
)

:: Enhanced GPU detection
echo [3/8] Detecting NVIDIA GPU...

:: First, try to find nvidia-smi in common locations
set "NVIDIA_SMI_FOUND=0"
set "NVIDIA_SMI_PATH="

:: Check if nvidia-smi is already in PATH
nvidia-smi --version >nul 2>&1
if not errorlevel 1 (
    set "NVIDIA_SMI_FOUND=1"
    set "NVIDIA_SMI_PATH=nvidia-smi"
    echo nvidia-smi found in PATH
    goto :gpu_detected
)

:: Check common NVIDIA installation paths
set "COMMON_PATHS="C:\Program Files\NVIDIA Corporation\NVSMI" "C:\Windows\System32" "C:\Program Files (x86)\NVIDIA Corporation\NVSMI""

for %%p in (!COMMON_PATHS!) do (
    if exist "%%~p\nvidia-smi.exe" (
        set "NVIDIA_SMI_FOUND=1"
        set "NVIDIA_SMI_PATH=%%~p\nvidia-smi.exe"
        echo nvidia-smi found at: %%~p
        :: Add to PATH for current session
        set "PATH=!PATH!;%%~p"
        goto :gpu_detected
    )
)

:: PowerShell fallback to detect NVIDIA GPU
echo Trying PowerShell GPU detection...
powershell -Command "Get-WmiObject -Class Win32_VideoController | Where-Object {$_.Name -like '*NVIDIA*'} | Select-Object -First 1 -ExpandProperty Name" >nul 2>&1
if not errorlevel 1 (
    echo NVIDIA GPU detected via PowerShell, but nvidia-smi not found.
    echo.
    echo IMPORTANT: nvidia-smi is required but not found in common locations.
    echo This usually means:
    echo 1. NVIDIA drivers are not installed
    echo 2. NVIDIA drivers are outdated
    echo 3. nvidia-smi is in an unusual location
    echo.
    echo Please:
    echo 1. Download and install the latest NVIDIA drivers from nvidia.com
    echo 2. Restart your computer
    echo 3. Run this script again
    echo.
    choice /C YN /M "Continue anyway (may cause issues later)? (Y/N)"
    if errorlevel 2 (
        pause
        exit /b 1
    )
    echo Continuing without nvidia-smi verification...
    set "GPU_NAME=NVIDIA GPU (detected via PowerShell)"
    set "PYTORCH_VERSION=2.6.0"
    set "CUDA_VERSION=cu124"
    goto :continue_installation
)

:: Final check - no NVIDIA GPU found
echo.
echo ========================================
echo    ERROR: No NVIDIA GPU Detected
echo ========================================
echo.
echo This application requires an NVIDIA GPU with CUDA support.
echo.
echo Troubleshooting steps:
echo 1. Ensure you have an NVIDIA GeForce/RTX/Quadro/Tesla GPU
echo 2. Download and install latest drivers from nvidia.com/drivers
echo 3. Restart your computer after driver installation
echo 4. Make sure your GPU supports CUDA (GTX 600 series or newer)
echo.
echo If you believe this is an error, you can:
echo - Check Device Manager for your GPU
echo - Run 'dxdiag' to see your graphics hardware
echo.
choice /C YN /M "Continue anyway (not recommended)? (Y/N)"
if errorlevel 2 (
    pause
    exit /b 1
)
echo Continuing at your own risk...
set "GPU_NAME=Unknown GPU"
set "PYTORCH_VERSION=2.6.0"
set "CUDA_VERSION=cu124"
goto :continue_installation

:gpu_detected
:: Get GPU info using maximum compatibility methods for old nvidia-smi versions
echo Getting GPU information...

:: Method 1: Use nvidia-smi -L (most compatible, works with very old versions)
for /f "tokens=3*" %%i in ('!NVIDIA_SMI_PATH! -L 2^>nul ^| findstr "GPU 0"') do (
    set GPU_NAME=%%j
    :: Remove "GeForce " prefix if present for cleaner output
    set GPU_NAME=!GPU_NAME:GeForce =!
    goto :gpu_name_found
)

:: Method 2: Fallback to basic nvidia-smi output parsing
if "!GPU_NAME!"=="" (
    echo Trying basic nvidia-smi parsing...
    for /f "tokens=*" %%i in ('!NVIDIA_SMI_PATH! 2^>nul ^| findstr /i "GeForce\|RTX\|GTX\|Quadro\|Tesla"') do (
        set GPU_LINE=%%i
        :: Extract GPU name from the line - look for common GPU identifiers
        echo !GPU_LINE! | findstr /i "RTX.*50" >nul && (
            set GPU_NAME=RTX 50 Series
            goto :gpu_name_found
        )
        echo !GPU_LINE! | findstr /i "RTX.*40" >nul && (
            set GPU_NAME=RTX 40 Series
            goto :gpu_name_found
        )
        echo !GPU_LINE! | findstr /i "RTX.*30" >nul && (
            set GPU_NAME=RTX 30 Series
            goto :gpu_name_found
        )
        echo !GPU_LINE! | findstr /i "RTX.*20" >nul && (
            set GPU_NAME=RTX 20 Series
            goto :gpu_name_found
        )
        echo !GPU_LINE! | findstr /i "GTX.*16" >nul && (
            set GPU_NAME=GTX 16 Series
            goto :gpu_name_found
        )
        echo !GPU_LINE! | findstr /i "GTX.*10" >nul && (
            set GPU_NAME=GTX 10 Series
            goto :gpu_name_found
        )
        echo !GPU_LINE! | findstr /i "GTX" >nul && (
            set GPU_NAME=GTX Series
            goto :gpu_name_found
        )
        echo !GPU_LINE! | findstr /i "RTX" >nul && (
            set GPU_NAME=RTX Series
            goto :gpu_name_found
        )
    )
)

:: Method 3: Last resort - just verify GPU exists
if "!GPU_NAME!"=="" (
    echo Warning: Advanced GPU detection failed, using basic detection...
    !NVIDIA_SMI_PATH! >nul 2>&1
    if not errorlevel 1 (
        set "GPU_NAME=NVIDIA GPU (basic detection)"
    )
)

:gpu_name_found
:: Check if we got GPU name
if "!GPU_NAME!"=="" (
    echo Warning: Could not retrieve GPU name, using default settings
    set "GPU_NAME=NVIDIA GPU (detection failed)"
    set "PYTORCH_VERSION=2.6.0"
    set "CUDA_VERSION=cu124"
    goto :continue_installation
)

:: Clean up GPU name - remove quotes, extra spaces, and parentheses
set "GPU_NAME=!GPU_NAME:"=!"
set "GPU_NAME=!GPU_NAME:(=!"
set "GPU_NAME=!GPU_NAME:)=!"
set "GPU_NAME=!GPU_NAME:  = !"

echo Detected GPU: !GPU_NAME!

:: Determine if RTX 50xx series
echo !GPU_NAME! | findstr /i "RTX.*50\|50.*Series" >nul
if not errorlevel 1 (
    set PYTORCH_VERSION=2.7.0
    set CUDA_VERSION=cu128
    echo RTX 50xx series detected - using PyTorch 2.7.0
) else (
    set PYTORCH_VERSION=2.6.0
    set CUDA_VERSION=cu124
    echo RTX 40xx or older detected - using PyTorch 2.6.0
)

:continue_installation
:: Clone repository
echo [4/8] Downloading Wan2GP source code...
if not exist "source" (
    git clone https://github.com/deepbeepmeep/Wan2GP.git source
    if errorlevel 1 (
        echo Failed to clone repository. Check your internet connection.
        pause
        exit /b 1
    )
)

cd source

:: Create virtual environment
echo [5/8] Creating Python virtual environment...
python -m venv wan2gp_env
if errorlevel 1 (
    echo Failed to create virtual environment.
    pause
    exit /b 1
)

:: Activate virtual environment
call wan2gp_env\Scripts\activate.bat

:: Upgrade pip
python -m pip install --upgrade pip

:: Install PyTorch
echo [6/8] Installing PyTorch !PYTORCH_VERSION! with !CUDA_VERSION!...
pip install torch==!PYTORCH_VERSION! torchvision torchaudio --index-url https://download.pytorch.org/whl/test/!CUDA_VERSION!
if errorlevel 1 (
    echo Failed to install PyTorch. Please check your internet connection.
    pause
    exit /b 1
)

:: Install requirements
echo [7/8] Installing Python dependencies...
pip install -r requirements.txt
if errorlevel 1 (
    echo Failed to install requirements. Continuing anyway...
)

:: Install optional performance enhancements
echo [8/8] Installing performance enhancements...

:: Install Triton for Windows
echo Installing Triton...
pip install triton-windows

:: Install SageAttention
echo Installing SageAttention...
pip install sageattention==1.0.6

:: Try to install SageAttention 2 (40% faster)
echo Installing SageAttention 2...
if "!PYTORCH_VERSION!"=="2.7.0" (
    pip install https://github.com/woct0rdho/SageAttention/releases/download/v2.1.1-windows/sageattention-2.1.1+cu128torch2.7.0-cp310-cp310-win_amd64.whl
) else (
    pip install https://github.com/woct0rdho/SageAttention/releases/download/v2.1.1-windows/sageattention-2.1.1+cu126torch2.6.0-cp310-cp310-win_amd64.whl
)

:: Try to install Flash Attention (may fail on some systems)
echo Installing Flash Attention (optional)...
pip install flash-attn==2.7.2.post1 2>nul || echo Flash Attention installation failed - continuing without it.

:: Create installation flag
echo Installation completed successfully! > ..\wan2gp_installed.flag

echo.
echo ========================================
echo    Installation Complete!
echo ========================================
echo.

:launch
:: Launch the application
cd source 2>nul || cd Wan2GP\source

:: Activate environment if not already active
if not defined VIRTUAL_ENV (
    call wan2gp_env\Scripts\activate.bat
)

echo Starting Wan2GP...
echo.
echo The application will open in your web browser at http://localhost:7860
echo Close this window to stop the application.
echo.

:: Launch with optimal settings
python wgp.py --open-browser --compile --attention sage2

:: Fallback to sage if sage2 fails
if errorlevel 1 (
    echo SageAttention 2 failed, trying SageAttention...
    python wgp.py --open-browser --compile --attention sage
)

:: Fallback to default if sage fails
if errorlevel 1 (
    echo SageAttention failed, using default attention...
    python wgp.py --open-browser --compile
)

:: Final fallback without compilation
if errorlevel 1 (
    echo Compilation failed, running without optimization...
    python wgp.py --open-browser
)

pause
