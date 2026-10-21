"""Package an unsigned archive. Side-loading tools must re-sign the resulting IPA."""
from pathlib import Path
import plistlib
import sys
import zipfile


def package(archive: Path, destination: Path):
    applications = archive / "Products/Applications"
    apps = list(applications.glob("*.app"))
    if len(apps) != 1:
        raise RuntimeError(f"Expected one .app, found {len(apps)}")
    app = apps[0]
    info = plistlib.loads((app / "Info.plist").read_bytes())
    if not (app / info["CFBundleExecutable"]).is_file():
        raise RuntimeError("Archive is missing its executable")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as output:
        for path in sorted(app.rglob("*")):
            if path.is_file():
                output.write(path, Path("Payload") / path.relative_to(applications))
    with zipfile.ZipFile(destination) as output:
        if output.testzip() is not None:
            raise RuntimeError("Corrupt IPA")
    print(f"Unsigned IPA: {destination} ({destination.stat().st_size:,} bytes); re-sign before installing.")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: package_ipa.py path/to/app.xcarchive output.ipa")
    package(Path(sys.argv[1]), Path(sys.argv[2]))
