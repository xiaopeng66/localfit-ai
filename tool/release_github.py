#!/usr/bin/env python3
"""创建/更新 LocalFit AI 的 GitHub Release（只放安装包，不推源码）。

用法（在仓库根目录）：
    python tool/release_github.py --ensure-repo
    python tool/release_github.py --notes-file docs/releases/v4095.md
    python tool/release_github.py --dry-run

约定：
* 发布仓库固定为 `xiaopeng66/localfit-ai-releases`（public，只有 README 与 Release）。
* tag 取 **arm64 的 versionCode**（`v4095`），与 `AppUpdateService` 的命名约定同源。
* 资产名固定 `LocalFitAI-vc<ABI code>-<abi>.apk`，由 `tool/build_release.dart` 生成。
* `api.github.com` **直连**（脚本显式禁用环境代理）；GitHub 网页/下载仍可走浏览器。
* 幂等：仓库已存在就复用。
* **版本必须单调**：新 arm64 versionCode 必须**大于**线上 latest，否则拒绝发布
  （2026-11-10 复盘：漏升版会发一个「检查更新永远看不到」的包）。已存在的
  Release tag 同理拒绝，覆盖必须显式 `--force`——旧实现对已存在 tag 静默走
  「更新」，同名同大小资产还会被跳过，发布结果不可信。
"""
from __future__ import annotations

import argparse
import json
import os
import re
import ssl
import subprocess
import urllib.error
import urllib.request
from pathlib import Path

OWNER = "xiaopeng66"
REPO_NAME = "localfit-ai-releases"
REPO = f"{OWNER}/{REPO_NAME}"
API_ROOT = "https://api.github.com"
USER_AGENT = "localfit-release"


def _opener() -> urllib.request.OpenerDirector:
    # 显式空 ProxyHandler：不读 HTTP(S)_PROXY。代理节点访问 api.github.com 会 403。
    # 证书用 certifi 的 CA 包：Windows/Miniconda 自带 OpenSSL 有时缺中间证书，
    # 报 `unable to get issuer certificate`（2026-11-02 实测），但仍保持校验。
    handlers: list[urllib.request.BaseHandler] = [urllib.request.ProxyHandler({})]
    try:
        import certifi

        context = ssl.create_default_context(cafile=certifi.where())
        handlers.append(urllib.request.HTTPSHandler(context=context))
    except ImportError:
        pass
    return urllib.request.build_opener(*handlers)


def token() -> str:
    env = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if env:
        return env.strip()
    try:
        out = subprocess.run(
            ["git", "credential", "fill"],
            input=b"protocol=https\nhost=github.com\n\n",
            capture_output=True,
            check=True,
        ).stdout.decode("utf-8", errors="replace")
    except (OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"no GitHub token available: {error}") from error
    for line in out.splitlines():
        if line.startswith("password="):
            return line.split("=", 1)[1].strip()
    raise SystemExit("git credential did not return a password")


def api(
    path: str,
    data: dict | None = None,
    *,
    method: str = "GET",
) -> tuple[int, object]:
    headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token()}",
        "User-Agent": USER_AGENT,
    }
    request = urllib.request.Request(
        f"{API_ROOT}{path}",
        data=None if data is None else json.dumps(data).encode("utf-8"),
        headers=headers,
        method=method,
    )
    try:
        with _opener().open(request, timeout=120) as response:
            raw = response.read()
            # GitHub 的 DELETE 返回 204 No Content：空 body 不是 JSON。
            # 旧实现无条件 json.loads ⇒ 重复发布（删旧资产后重传）时在删除
            # 成功的下一步崩掉，资产半删半留。空 body 统一回 {}。
            if not raw:
                return response.status, {}
            return response.status, json.loads(raw.decode("utf-8"))
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        try:
            payload = json.loads(body)
        except ValueError:
            payload = {"message": body}
        return error.code, payload


def upload(upload_url: str, path: Path) -> tuple[int, object]:
    body = path.read_bytes()
    request = urllib.request.Request(
        upload_url.split("{")[0] + f"?name={path.name}",
        data=body,
        headers={
            "Authorization": f"Bearer {token()}",
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/vnd.android.package-archive",
            "Content-Length": str(len(body)),
            "User-Agent": USER_AGENT,
        },
        method="POST",
    )
    try:
        with _opener().open(request, timeout=1800) as response:
            return response.status, json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        return error.code, json.loads(
            error.read().decode("utf-8", errors="replace")
        )


def ensure_repo() -> None:
    status, payload = api(f"/repos/{REPO}")
    if status == 200:
        print(f"repo exists: {REPO}")
        return
    if status != 404:
        raise SystemExit(f"repo lookup failed: {status} {payload}")
    status, payload = api(
        "/user/repos",
        {
            "name": REPO_NAME,
            "description": "LocalFit AI 安装包发布（仅 Release，不含源码）",
            "private": False,
            "auto_init": True,
            "has_issues": False,
            "has_wiki": False,
            "has_projects": False,
        },
        method="POST",
    )
    if status >= 300:
        raise SystemExit(f"repo create failed: {status} {payload}")
    print(f"repo created: {payload['html_url']}")


def version_codes() -> tuple[int, list[Path]]:
    """读 pubspec 构建号，返回 (arm64 versionCode, 三个 APK 路径)。"""
    text = Path("pubspec.yaml").read_text(encoding="utf-8")
    match = re.search(
        r"^version:\s*[0-9.]+\+(\d+)\s*$", text, flags=re.MULTILINE
    )
    if match is None:
        raise SystemExit("pubspec.yaml 里找不到 version: x.y.z+N")
    build = int(match.group(1))
    arm64 = build + 2000
    expected = {
        "arm32": build + 1000,
        "arm64": arm64,
        "x86_64": build + 4000,
    }
    files: list[Path] = []
    for abi, code in expected.items():
        path = Path("dist") / f"LocalFitAI-vc{code}-{abi}.apk"
        if not path.is_file():
            raise SystemExit(
                f"缺少安装包：{path}（先跑 dart run tool/build_release.dart）"
            )
        files.append(path)
    return arm64, files


def parse_version_code(tag: str | None) -> int | None:
    """从 release tag（`v4142`）里取 versionCode；认不出返回 None。"""
    if tag is None:
        return None
    match = re.fullmatch(r"v(\d+)", tag.strip())
    return int(match.group(1)) if match else None


def check_version_monotonic(new_code: int, latest_tag: str | None) -> None:
    """新 versionCode 必须严格大于线上 latest，否则拒绝发布。"""
    latest = parse_version_code(latest_tag)
    if latest is None:
        return
    if new_code <= latest:
        raise SystemExit(
            f"拒绝发布：新 versionCode {new_code} 不大于线上 latest "
            f"{latest_tag}。漏升版会发出一个「检查更新永远看不到」的包；"
            f"先在 pubspec.yaml 升构建号，确要覆盖时用 --force。"
        )


def latest_release() -> tuple[int, object]:
    return api(f"/repos/{REPO}/releases/latest")


def body_from_args(args: argparse.Namespace, tag: str) -> str:
    if args.body:
        return args.body
    if args.notes_file:
        text = Path(args.notes_file).read_text(encoding="utf-8").strip()
        if text:
            return text
    return f"LocalFit AI {tag}"


def publish(
    tag: str,
    files: list[Path],
    body: str,
    dry_run: bool,
    force: bool,
) -> int:
    if dry_run:
        print(f"[dry-run] repo={REPO} tag={tag}")
        for path in files:
            print(f"[dry-run] upload {path.name} ({path.stat().st_size} B)")
        return 0

    status, release = api(f"/repos/{REPO}/releases/tags/{tag}")
    if status == 404:
        status, release = api(
            f"/repos/{REPO}/releases",
            {
                "tag_name": tag,
                "name": f"LocalFit AI {tag}",
                "body": body,
                "draft": False,
                "prerelease": False,
            },
            method="POST",
        )
        if status >= 300:
            print(f"release create failed: {status} {release}")
            return 1
        print(f"release created: {tag} id={release['id']}")
    elif status == 200 and not force:
        print(
            f"refuse to overwrite existing release: {tag}（确认要覆盖时加 --force，"
            f"并逐个重下资产核对 SHA-256）"
        )
        return 1
    elif status == 200:
        status, release = api(
            f"/repos/{REPO}/releases/{release['id']}",
            {"name": f"LocalFit AI {tag}", "body": body, "draft": False},
            method="PATCH",
        )
        if status >= 300:
            print(f"release update failed: {status} {release}")
            return 1
        print(f"release updated: {tag}")
    else:
        print(f"release lookup failed: {status} {release}")
        return 1

    upload_url = release["upload_url"]
    assets = {asset["name"]: asset for asset in release.get("assets", [])}
    for path in files:
        existing = assets.get(path.name)
        if existing is not None and existing.get("size") == path.stat().st_size:
            print(f"skip existing asset: {path.name}")
            continue
        if existing is not None:
            status, payload = api(
                f"/repos/{REPO}/releases/assets/{existing['id']}",
                method="DELETE",
            )
            if status >= 300:
                print(f"asset delete failed: {path.name}: {status} {payload}")
                return 1
        status, result = upload(upload_url, path)
        if status >= 300:
            print(f"upload failed for {path.name}: {status} {result}")
            return 1
        print(f"uploaded {result['name']} ({result['size']} B)")

    status, latest = api(f"/repos/{REPO}/releases/latest")
    print(f"latest: {latest.get('tag_name')} ({status})")
    print(f"release page: https://github.com/{REPO}/releases/tag/{tag}")
    for asset in latest.get("assets", []):
        print(f"  {asset['name']} -> {asset['browser_download_url']}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="LocalFit AI GitHub Release")
    parser.add_argument("--ensure-repo", action="store_true", help="只创建/确认发布仓库")
    parser.add_argument("--tag", default=None, help="默认 v<arm64 versionCode>")
    parser.add_argument("--body", default=None)
    parser.add_argument("--notes-file", default=None)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--force",
        action="store_true",
        help="允许覆盖已存在的同名 Release（默认拒绝）",
    )
    args = parser.parse_args()

    ensure_repo()
    if args.ensure_repo:
        return 0

    arm64, files = version_codes()
    tag = args.tag or f"v{arm64}"
    body = body_from_args(args, tag)

    status, latest = latest_release()
    if status == 200:
        check_version_monotonic(arm64, latest.get("tag_name"))
    elif status != 404:
        raise SystemExit(
            f"无法确认线上 latest（status {status}）；发布前必须能比对版本，"
            f"确要继续用 --force。"
        )
    return publish(tag, files, body, args.dry_run, args.force)


if __name__ == "__main__":
    raise SystemExit(main())
