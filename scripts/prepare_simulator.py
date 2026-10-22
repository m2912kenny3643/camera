"""Create and boot a dedicated, available iPhone 17 simulator for the UI job."""
import json
import os
from pathlib import Path
import subprocess


def query(kind):
    return json.loads(subprocess.check_output(["xcrun", "simctl", "list", kind, "--json"], text=True))


def create_compatible_simulator(device_type, runtimes):
    for runtime in sorted(runtimes, key=lambda item: tuple(int(part) for part in item["version"].split(".")), reverse=True):
        result = subprocess.run(["xcrun", "simctl", "create", "R6Camera-CI", device_type, runtime["identifier"]],
                                text=True, capture_output=True)
        if result.returncode == 0:
            return result.stdout.strip(), runtime
        # An installed newer runtime can be available yet incompatible with selected Xcode.
        if "incompatible device" not in result.stderr.lower():
            raise RuntimeError(f"Simulator creation failed: {result.stderr.strip()}")
        print(f"Skipping incompatible runtime {runtime['version']}: {result.stderr.strip()}", flush=True)
    raise RuntimeError("No compatible iPhone 17 / iOS 27 runtime for the selected Xcode")


def prepare():
    devices = query("devicetypes")["devicetypes"]
    device_type = next(item["identifier"] for item in devices if item["name"] == "iPhone 17")
    runtimes = [item for item in query("runtimes")["runtimes"]
                if item.get("isAvailable") and "SimRuntime.iOS-" in item["identifier"]
                and item["version"].split(".")[0] == "27"]
    if not runtimes:
        raise RuntimeError("No available iOS 27 simulator runtime")
    simulator, runtime = create_compatible_simulator(device_type, runtimes)
    print(f"Dedicated simulator: {simulator}; runtime {runtime['version']}", flush=True)
    subprocess.run(["xcrun", "simctl", "boot", simulator], check=True, timeout=60)
    subprocess.run(["xcrun", "simctl", "bootstatus", simulator, "-b"], check=True, timeout=300)
    with Path(os.environ["GITHUB_ENV"]).open("a", encoding="utf-8") as stream:
        stream.write(f"R6_SIMULATOR_UDID={simulator}\n")


if __name__ == "__main__":
    prepare()
