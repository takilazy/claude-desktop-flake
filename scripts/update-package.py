#!/usr/bin/env python3
"""Update package.nix from Anthropic's stable Debian repository metadata."""

from __future__ import annotations

import pathlib
import re
import urllib.request


REPOSITORY = "https://downloads.claude.ai/claude-desktop/apt/stable"
ARCHITECTURES = {
    "amd64": "x86_64-linux",
    "arm64": "aarch64-linux",
}
PACKAGE_NIX = pathlib.Path(__file__).resolve().parents[1] / "package.nix"


def fetch_package(architecture: str) -> dict[str, str]:
    url = f"{REPOSITORY}/dists/stable/main/binary-{architecture}/Packages"
    request = urllib.request.Request(url, headers={"User-Agent": "claude-desktop-flake-updater"})
    with urllib.request.urlopen(request, timeout=30) as response:
        contents = response.read().decode()

    candidates = []
    for paragraph in contents.split("\n\n"):
        fields = dict(
            line.split(": ", 1)
            for line in paragraph.splitlines()
            if ": " in line
        )
        if fields.get("Package") == "claude-desktop":
            missing = {"Version", "SHA256"} - fields.keys()
            if missing:
                raise RuntimeError(f"{url} is missing fields: {', '.join(sorted(missing))}")
            candidates.append(fields)

    if not candidates:
        raise RuntimeError(f"claude-desktop was not found in {url}")

    def version_key(package: dict[str, str]) -> tuple[int, ...]:
        version = package["Version"]
        if not re.fullmatch(r"\d+(?:\.\d+)*", version):
            raise RuntimeError(f"unsupported Debian version format in {url}: {version}")
        return tuple(map(int, version.split(".")))

    return max(candidates, key=version_key)


def replace_once(text: str, pattern: str, replacement: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise RuntimeError(f"expected exactly one match for {pattern!r}")
    return updated


def main() -> None:
    packages = {arch: fetch_package(arch) for arch in ARCHITECTURES}
    versions = {package["Version"] for package in packages.values()}
    if len(versions) != 1:
        details = ", ".join(f"{arch}={pkg['Version']}" for arch, pkg in packages.items())
        raise RuntimeError(f"repository architectures are out of sync: {details}")

    version = versions.pop()
    contents = PACKAGE_NIX.read_text()
    contents = replace_once(
        contents,
        r'^(  version = ")[^"]+(";)$',
        rf"\g<1>{version}\g<2>",
    )

    for architecture, system in ARCHITECTURES.items():
        sha256 = packages[architecture]["SHA256"]
        pattern = rf'(    {re.escape(system)} = fetchurl \{{[\s\S]*?^      hash = "sha256:)[^"]+(";)$'
        contents = replace_once(contents, pattern, rf"\g<1>{sha256}\g<2>")

    PACKAGE_NIX.write_text(contents)
    print(f"claude-desktop {version}")


if __name__ == "__main__":
    main()
