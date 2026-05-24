import os
import sys
import platform
import subprocess

def get_ram_gb():
    try:
        if platform.system() == "Windows":
            # Use PowerShell to get Total Physical Memory
            cmd = ["powershell", "-NoProfile", "-Command", "(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory"]
            res = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode().strip()
            return round(int(res) / (1024**3))
        elif platform.system() == "Darwin":
            cmd = ["sysctl", "-n", "hw.memsize"]
            res = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode().strip()
            return round(int(res) / (1024**3))
        elif platform.system() == "Linux":
            with open("/proc/meminfo", "r") as f:
                for line in f:
                    if "MemTotal" in line:
                        kb = int(line.split()[1])
                        return round(kb / (1024**2))
    except Exception:
        pass
    return 8  # Default fallback

def get_cpu_cores():
    try:
        return os.cpu_count() or 4
    except Exception:
        return 4

def get_gpu_info():
    gpu_name = "None/CPU Only"
    vram_gb = 0
    is_nvidia = False
    is_apple_silicon = False

    try:
        # Check for Apple Silicon first
        if platform.system() == "Darwin":
            cmd = ["sysctl", "-n", "machdep.cpu.brand_string"]
            brand = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode().strip()
            if "Apple" in brand:
                is_apple_silicon = True
                gpu_name = brand
                # Apple Silicon uses unified memory, so VRAM is essentially total RAM
                vram_gb = get_ram_gb()
                return gpu_name, vram_gb, is_nvidia, is_apple_silicon

        # Check for nvidia-smi
        try:
            res = subprocess.check_output(["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader,nounits"], stderr=subprocess.DEVNULL).decode().strip()
            if res:
                parts = res.split(",")
                gpu_name = parts[0].strip()
                vram_mb = int(parts[1].strip())
                vram_gb = round(vram_mb / 1024)
                is_nvidia = True
                return gpu_name, vram_gb, is_nvidia, is_apple_silicon
        except Exception:
            pass

        # Platform-specific fallback checks
        if platform.system() == "Windows":
            cmd = ["powershell", "-NoProfile", "-Command", "Get-CimInstance Win32_VideoController | Select-Object Name, AdapterRAM | ConvertTo-Json"]
            res = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode().strip()
            if res:
                import json
                data = json.loads(res)
                if isinstance(data, list):
                    gpu = data[0]
                else:
                    gpu = data
                gpu_name = gpu.get("Name", "Unknown GPU")
                vram_bytes = gpu.get("AdapterRAM", 0)
                # Sometimes WMI returns negative or large numbers for high VRAM, handle safely
                if vram_bytes and vram_bytes > 0:
                    vram_gb = round(vram_bytes / (1024**3))
                if "NVIDIA" in gpu_name.upper():
                    is_nvidia = True
        elif platform.system() == "Linux":
            # Simple lspci check
            res = subprocess.check_output("lspci | grep -i 'vga\\|3d'", shell=True, stderr=subprocess.DEVNULL).decode().strip()
            if res:
                gpu_name = res.split(":")[-1].strip()
                if "NVIDIA" in gpu_name.upper():
                    is_nvidia = True
    except Exception:
        pass

    return gpu_name, vram_gb, is_nvidia, is_apple_silicon

def main():
    ram = get_ram_gb()
    cores = get_cpu_cores()
    gpu_name, vram, is_nvidia, is_apple_silicon = get_gpu_info()

    # ANSI Colors
    RESET = "\033[0m"
    BOLD = "\033[1m"
    CYAN = "\033[36m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    GRAY = "\033[90m"

    print(f"{CYAN}--- System Specification Detect ---{RESET}")
    print(f"  {BOLD}CPU Cores:{RESET}  {cores}")
    print(f"  {BOLD}System RAM:{RESET} {ram} GB")
    print(f"  {BOLD}GPU Device:{RESET} {gpu_name}")
    if vram > 0 and not is_apple_silicon:
        print(f"  {BOLD}GPU VRAM:{RESET}   {vram} GB")
    elif is_apple_silicon:
        print(f"  {BOLD}Memory:{RESET}     Unified Memory ({ram} GB)")
    print(f"{CYAN}----------------------------------{RESET}")
    print("")

    # Determine recommendation
    print(f"{GREEN}{BOLD}Hermes Recommendation:{RESET}")
    if is_apple_silicon:
        if ram >= 16:
            print(f"  * Apple Silicon detected with {ram}GB Unified Memory.")
            print(f"  * {YELLOW}Recommendation:{RESET} We highly recommend {BOLD}Qwen 2.5 Coder 7B{RESET} or {BOLD}Gemma 4 E4B{RESET} for best balance.")
        else:
            print(f"  * Apple Silicon detected with {ram}GB Unified Memory.")
            print(f"  * {YELLOW}Recommendation:{RESET} We recommend {BOLD}Qwen 2.5 Coder 1.5B{RESET} or {BOLD}Gemma 4 E2B{RESET} for fast performance.")
    elif is_nvidia and vram >= 6:
        print(f"  * NVIDIA GPU detected with {vram}GB dedicated VRAM.")
        print(f"  * {YELLOW}Recommendation:{RESET} We highly recommend {BOLD}Qwen 2.5 Coder 7B{RESET}, {BOLD}Gemma 4 E4B{RESET}, or {BOLD}DeepSeek-Coder 6.7B{RESET} (GPU-accelerated).")
    elif ram >= 16:
        print(f"  * CPU setup detected with {ram}GB system RAM.")
        print(f"  * {YELLOW}Recommendation:{RESET} We recommend {BOLD}Qwen 2.5 Coder 1.5B{RESET}, {BOLD}Gemma 4 E2B{RESET}, or {BOLD}DeepSeek-Coder 1.3B{RESET} (CPU mode).")
        print(f"    You can try 7B models, but generation speeds may be slower.")
    else:
        print(f"  * Low resource system detected ({ram}GB RAM, CPU-only).")
        print(f"  * {YELLOW}Recommendation:{RESET} Please choose lightweight models: {BOLD}Qwen 2.5 Coder 1.5B{RESET}, {BOLD}Gemma 4 E2B{RESET}, or {BOLD}DeepSeek-Coder 1.3B{RESET}.")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--recommend-tags":
        ram = get_ram_gb()
        gpu_name, vram, is_nvidia, is_apple_silicon = get_gpu_info()
        recs = []
        if is_apple_silicon:
            if ram >= 16:
                recs = ["qwen2.5-coder:7b", "gemma4:e4b"]
            else:
                recs = ["qwen2.5-coder:1.5b", "gemma4:e2b"]
        elif is_nvidia and vram >= 6:
            recs = ["qwen2.5-coder:7b", "gemma4:e4b", "deepseek-coder:6.7b"]
        else:
            recs = ["qwen2.5-coder:1.5b", "gemma4:e2b", "deepseek-coder:1.3b"]
        print(" ".join(recs))
        sys.exit(0)

    main()
