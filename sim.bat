@echo off
REM CNN Accelerator Simulation Script for Windows
REM Usage: sim.bat [test_name]
REM Available tests: cnn, multiplier, mac, divider, div9, all

set SRC_DIR=src
set TB_DIR=tb
set OUT_DIR=sim_output
set VCD_DIR=sim_output\waveforms

REM Create output directories
if not exist sim_output mkdir sim_output
if not exist sim_output\waveforms mkdir sim_output\waveforms

REM Parse command line argument
set TEST=%1
if "%TEST%"=="" set TEST=cnn

echo ========================================
echo CNN Accelerator Simulation
echo ========================================

if /I "%TEST%"=="cnn" goto run_cnn
if /I "%TEST%"=="multiplier" goto run_multiplier
if /I "%TEST%"=="mac" goto run_mac
if /I "%TEST%"=="divider" goto run_divider
if /I "%TEST%"=="div9" goto run_div9
if /I "%TEST%"=="all" goto run_all
if /I "%TEST%"=="clean" goto clean
if /I "%TEST%"=="help" goto help

echo Unknown test: %TEST%
goto help

:run_cnn
echo.
echo === Compiling CNN Accelerator ===
iverilog -g2012 -o %OUT_DIR%\cnn_accelerator.vvp ^
    %SRC_DIR%\multiplier.v ^
    %SRC_DIR%\MAC.v ^
    %SRC_DIR%\divider_Version2.v ^
    %SRC_DIR%\divide_by_9_Version2.v ^
    %SRC_DIR%\controller_Version2.v ^
    %SRC_DIR%\cnn_accelerator_Version2.v ^
    %TB_DIR%\cnn_accelerator_tb_Version2.v

if %ERRORLEVEL% NEQ 0 (
    echo Compilation failed!
    exit /b 1
)

echo === Running CNN Accelerator Simulation ===
cd %OUT_DIR%
vvp cnn_accelerator.vvp
cd ..

if exist "cnn_accelerator_tb.vcd" move /Y "cnn_accelerator_tb.vcd" "%VCD_DIR%\"
if exist "%OUT_DIR%\cnn_accelerator_tb.vcd" move /Y "%OUT_DIR%\cnn_accelerator_tb.vcd" "%VCD_DIR%\"

echo === Simulation Complete ===
echo Waveform saved to %VCD_DIR%\cnn_accelerator_tb.vcd
goto end

:run_multiplier
echo.
echo === Compiling Multiplier ===
iverilog -g2012 -o %OUT_DIR%\multiplier.vvp ^
    %SRC_DIR%\multiplier.v ^
    %TB_DIR%\multiplier_tb_Version2.v

if %ERRORLEVEL% NEQ 0 (
    echo Compilation failed!
    exit /b 1
)

echo === Running Multiplier Simulation ===
cd %OUT_DIR%
vvp multiplier.vvp
cd ..

if exist "multiplier_tb.vcd" move /Y "multiplier_tb.vcd" "%VCD_DIR%\"
if exist "%OUT_DIR%\multiplier_tb.vcd" move /Y "%OUT_DIR%\multiplier_tb.vcd" "%VCD_DIR%\"

echo === Simulation Complete ===
goto end

:run_mac
echo.
echo === Compiling MAC ===
iverilog -g2012 -o %OUT_DIR%\mac.vvp ^
    %SRC_DIR%\multiplier.v ^
    %SRC_DIR%\MAC.v ^
    %TB_DIR%\mac_tb_Version2.v

if %ERRORLEVEL% NEQ 0 (
    echo Compilation failed!
    exit /b 1
)

echo === Running MAC Simulation ===
cd %OUT_DIR%
vvp mac.vvp
cd ..

if exist "mac_tb.vcd" move /Y "mac_tb.vcd" "%VCD_DIR%\"
if exist "%OUT_DIR%\mac_tb.vcd" move /Y "%OUT_DIR%\mac_tb.vcd" "%VCD_DIR%\"

echo === Simulation Complete ===
goto end

:run_divider
echo.
echo === Compiling Divider ===
iverilog -g2012 -o %OUT_DIR%\divider.vvp ^
    %SRC_DIR%\divider_Version2.v ^
    %TB_DIR%\divider_tb_Version2.v

if %ERRORLEVEL% NEQ 0 (
    echo Compilation failed!
    exit /b 1
)

echo === Running Divider Simulation ===
cd %OUT_DIR%
vvp divider.vvp
cd ..

if exist "divider_tb.vcd" move /Y "divider_tb.vcd" "%VCD_DIR%\"
if exist "%OUT_DIR%\divider_tb.vcd" move /Y "%OUT_DIR%\divider_tb.vcd" "%VCD_DIR%\"

echo === Simulation Complete ===
goto end

:run_div9
echo.
echo === Compiling Divide-by-9 ===
iverilog -g2012 -o %OUT_DIR%\div9.vvp ^
    %SRC_DIR%\divide_by_9_Version2.v ^
    %TB_DIR%\divide_by_9_Version2.v

if %ERRORLEVEL% NEQ 0 (
    echo Compilation failed!
    exit /b 1
)

echo === Running Divide-by-9 Simulation ===
cd %OUT_DIR%
vvp div9.vvp
cd ..

if exist "divide_by_9_tb.vcd" move /Y "divide_by_9_tb.vcd" "%VCD_DIR%\"
if exist "%OUT_DIR%\divide_by_9_tb.vcd" move /Y "%OUT_DIR%\divide_by_9_tb.vcd" "%VCD_DIR%\"

echo === Simulation Complete ===
goto end

:run_all
call :run_multiplier
call :run_mac
call :run_divider
call :run_div9
call :run_cnn
echo.
echo === All Tests Complete ===
goto end

:clean
echo Cleaning simulation outputs...
if exist "%OUT_DIR%" rd /s /q "%OUT_DIR%"
if exist "*.vcd" del /q "*.vcd"
if exist "*.vvp" del /q "*.vvp"
echo === Cleaned ===
goto end

:help
echo.
echo CNN Accelerator Simulation Script
echo ==================================
echo Usage: sim.bat [test_name]
echo.
echo Available tests:
echo   cnn         - Run CNN accelerator simulation (default)
echo   multiplier  - Run multiplier testbench
echo   mac         - Run MAC testbench
echo   divider     - Run divider testbench
echo   div9        - Run divide-by-9 testbench
echo   all         - Run all testbenches
echo   clean       - Remove all simulation outputs
echo   help        - Show this help message
echo.
echo Examples:
echo   sim.bat              (runs CNN accelerator)
echo   sim.bat multiplier   (runs multiplier test)
echo   sim.bat all          (runs all tests)
goto end

:end
