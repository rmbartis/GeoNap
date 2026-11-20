#!/usr/bin/env python3
# Copyright © 2026 Robert Bartis. All rights reserved.
"""
Upload GeoNap App Store metadata from appstore/metadata/<locale>/*.txt
to App Store Connect via the App Store Connect API.

DRY RUN BY DEFAULT: prints what would change. Pass --apply to write.
Nothing is written if any problem is found — all checks run first.

Files per locale folder (all optional — a missing file leaves that field as is):
  On the version page:
    keywords.txt            (max 100 characters, no spaces after commas)
    whats_new.txt           (max 4000; not allowed on an app's very first version)
    description.txt         (max 4000)
    promotional_text.txt    (max 170; can change any time, no review needed)
    support_url.txt         (a URL)
  On App Information (shared by all versions):
    name.txt                (max 30; if missing, a NEW language copies the primary language's name)
    subtitle.txt            (max 30)
    privacy_policy_url.txt  (a URL; if missing, a NEW language copies the primary language's)

A NEW language (--create-missing) must have description, keywords and a support URL,
because App Store Connect won't accept a submission without them.

Setup (once):
    pip3 install pyjwt cryptography requests
    App Store Connect > Users and Access > Integrations > App Store Connect API:
      create a Team key with the "App Manager" role, download AuthKey_XXXX.p8
      (download is one-time; keep it OUT of git — *.p8 is in .gitignore).
    export ASC_KEY_ID=XXXXXXXXXX
    export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    export ASC_KEY_PATH=~/.appstoreconnect/AuthKey_XXXXXXXXXX.p8

Usage:
    python3 appstore/upload_metadata.py --version 1.1.0                     # dry run
    python3 appstore/upload_metadata.py --version 1.1.0 --apply             # write
    add --create-missing to add languages that aren't on the listing yet
    add --only de-DE,fr-FR to limit the run to some languages
"""
import argparse, os, sys, time
from pathlib import Path

try:
    import jwt, requests
except ImportError:
    sys.exit("Missing packages. Run: pip3 install pyjwt cryptography requests")

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "com.rmbartis.GeoNap"
METADATA_DIR = Path(__file__).resolve().parent / "metadata"

# file name -> (API attribute, max chars, lives on "version" or "appinfo")
FIELDS = {
    "keywords.txt":           ("keywords",         100,  "version"),
    "whats_new.txt":          ("whatsNew",         4000, "version"),
    "description.txt":        ("description",      4000, "version"),
    "promotional_text.txt":   ("promotionalText",  170,  "version"),
    "support_url.txt":        ("supportUrl",       255,  "version"),
    "name.txt":               ("name",             30,   "appinfo"),
    "subtitle.txt":           ("subtitle",         30,   "appinfo"),
    "privacy_policy_url.txt": ("privacyPolicyUrl", 255,  "appinfo"),
}
REQUIRED_FOR_NEW = ["description", "keywords", "supportUrl"]
LIVE_STATES = {"READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "REPLACED_WITH_NEW_INFO"}


def token():
    key_path = os.path.expanduser(os.environ.get("ASC_KEY_PATH", ""))
    kid, iss = os.environ.get("ASC_KEY_ID"), os.environ.get("ASC_ISSUER_ID")
    if not (key_path and kid and iss):
        sys.exit("Set ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (see the top of this file).")
    now = int(time.time())
    return jwt.encode({"iss": iss, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
                      Path(key_path).read_text(), algorithm="ES256",
                      headers={"kid": kid, "typ": "JWT"})


class ASC:
    def __init__(self):
        self.s = requests.Session()
        self.s.headers["Authorization"] = f"Bearer {token()}"

    def call(self, method, path, **kw):
        r = self.s.request(method, API + path, timeout=30, **kw)
        if r.status_code >= 400:
            sys.exit(f"{method} {path} failed: HTTP {r.status_code}\n{r.text}")
        return r.json() if r.text else {}

    def get_all(self, path, params=None):
        out, url, params = [], API + path, dict(params or {}, limit=200)
        while url:
            r = self.s.get(url, params=params, timeout=30)
            if r.status_code >= 400:
                sys.exit(f"GET {url} failed: HTTP {r.status_code}\n{r.text}")
            j = r.json(); out += j["data"]; url = j.get("links", {}).get("next"); params = None
        return out


def load_local(only=None):
    """{locale: {filename: text}} from appstore/metadata, with length checks."""
    data, errors = {}, []
    for loc_dir in sorted(p for p in METADATA_DIR.iterdir() if p.is_dir()):
        if only and loc_dir.name not in only:
            continue
        files = {}
        for fname, (_, limit, _) in FIELDS.items():
            f = loc_dir / fname
            if f.exists():
                text = f.read_text(encoding="utf-8").strip()
                if len(text) > limit:
                    errors.append(f"{loc_dir.name}/{fname}: {len(text)} chars (max {limit})")
                if fname == "keywords.txt" and ", " in text:
                    errors.append(f"{loc_dir.name}/keywords.txt: remove spaces after commas")
                if fname.endswith("_url.txt") and not text.startswith("https://"):
                    errors.append(f"{loc_dir.name}/{fname}: must start with https://")
                files[fname] = text
        if files:
            data[loc_dir.name] = files
    if errors:
        sys.exit("Fix these before uploading:\n  " + "\n  ".join(errors))
    return data


def show(locale, attr, old, new):
    one = lambda v: (v or "").replace("\n", " ⏎ ")
    print(f"  [{locale}] {attr}:\n      now: {one(old)[:110]}\n      new: {one(new)[:110]}")


def state_of(info):
    a = info["attributes"]
    return a.get("state") or a.get("appStoreState") or "?"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--version", required=True, help="App Store version string, e.g. 1.1.0")
    ap.add_argument("--apply", action="store_true", help="write changes (default: dry run)")
    ap.add_argument("--create-missing", action="store_true", help="add languages that don't exist yet")
    ap.add_argument("--only", help="comma-separated locales to include, e.g. de-DE,fr-FR")
    args = ap.parse_args()
    only = set(args.only.split(",")) if args.only else None

    local = load_local(only)
    asc = ASC()
    apps = asc.get_all("/apps", {"filter[bundleId]": BUNDLE_ID})
    if not apps:
        sys.exit(f"No app with bundle ID {BUNDLE_ID}")
    app_id, primary = apps[0]["id"], apps[0]["attributes"].get("primaryLocale", "en-US")

    versions = asc.get_all(f"/apps/{app_id}/appStoreVersions",
                           {"filter[platform]": "IOS", "filter[versionString]": args.version})
    if not versions:
        sys.exit(f"No iOS version {args.version} in App Store Connect — create or rename it first.")
    version_id = versions[0]["id"]
    remote = {l["attributes"]["locale"]: l for l in
              asc.get_all(f"/appStoreVersions/{version_id}/appStoreVersionLocalizations")}

    # App Information: the editable one is the one that isn't live yet.
    infos = asc.get_all(f"/apps/{app_id}/appInfos")
    editable = [i for i in infos if state_of(i) not in LIVE_STATES] or infos
    info_id = editable[0]["id"]
    info_locs = {l["attributes"]["locale"]: l for l in
                 asc.get_all(f"/appInfos/{info_id}/appInfoLocalizations")}
    primary_info = info_locs.get(primary, {}).get("attributes", {})

    print(f"App {app_id}, version {args.version} ({version_id}), primary language {primary}")
    print(f"App Information record: {info_id} ({state_of(editable[0])})")
    print(f"Existing App Store languages: {', '.join(sorted(remote)) or 'none'}")
    print(f"Local metadata folders:       {', '.join(sorted(local))}\n")

    actions, problems = [], []   # actions: (method, path, payload)
    for locale, files in local.items():
        v_attrs = {FIELDS[f][0]: t for f, t in files.items() if FIELDS[f][2] == "version"}
        a_attrs = {FIELDS[f][0]: t for f, t in files.items() if FIELDS[f][2] == "appinfo"}

        # --- version page (description, keywords, What's New, ...) ---
        rec = remote.get(locale)
        if rec is None:
            if not args.create_missing:
                print(f"  [{locale}] SKIPPED — not on the listing yet (re-run with --create-missing)")
                continue
            missing = [k for k in REQUIRED_FOR_NEW if not v_attrs.get(k)]
            if missing:
                problems.append(f"{locale}: a new language needs {', '.join(missing)}")
            print(f"  [{locale}] NEW language — version page with: {', '.join(v_attrs)}")
            actions.append(("POST", "/appStoreVersionLocalizations", {"data": {
                "type": "appStoreVersionLocalizations",
                "attributes": dict(v_attrs, locale=locale),
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}}))
        else:
            diff = {k: v for k, v in v_attrs.items() if (rec["attributes"].get(k) or "").strip() != v}
            for k, v in diff.items():
                show(locale, k, rec["attributes"].get(k), v)
            if diff:
                actions.append(("PATCH", f"/appStoreVersionLocalizations/{rec['id']}", {"data": {
                    "type": "appStoreVersionLocalizations", "id": rec["id"], "attributes": diff}}))

        # --- App Information (name, subtitle, privacy policy URL) ---
        irec = info_locs.get(locale)
        if irec is None:
            if not args.create_missing:
                if a_attrs:
                    print(f"  [{locale}] App Information SKIPPED — language not added yet")
                continue
            attrs = dict(a_attrs)
            attrs.setdefault("name", primary_info.get("name"))
            if primary_info.get("privacyPolicyUrl"):
                attrs.setdefault("privacyPolicyUrl", primary_info["privacyPolicyUrl"])
            if not attrs.get("name"):
                problems.append(f"{locale}: no app name (add name.txt)")
            print(f"  [{locale}] NEW language — App Information: name \"{attrs.get('name')}\""
                  + (f", subtitle \"{attrs['subtitle']}\"" if attrs.get("subtitle") else ""))
            actions.append(("POST", "/appInfoLocalizations", {"data": {
                "type": "appInfoLocalizations",
                "attributes": dict({k: v for k, v in attrs.items() if v}, locale=locale),
                "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info_id}}}}}))
        else:
            diff = {k: v for k, v in a_attrs.items() if (irec["attributes"].get(k) or "").strip() != v}
            for k, v in diff.items():
                show(locale, k, irec["attributes"].get(k), v)
            if diff:
                actions.append(("PATCH", f"/appInfoLocalizations/{irec['id']}", {"data": {
                    "type": "appInfoLocalizations", "id": irec["id"], "attributes": diff}}))

    if problems:
        sys.exit("\nNothing written. Fix these first:\n  " + "\n  ".join(problems))
    if not actions:
        print("Everything already matches — nothing to do.")
        return
    if not args.apply:
        print(f"\nDRY RUN: {len(actions)} change(s) would be made. Re-run with --apply to write them.")
        return
    for i, (method, path, payload) in enumerate(actions, 1):
        if path == "/appInfoLocalizations":
            # Adding a language's version page makes Apple create its App Information
            # entry automatically (it may take a few seconds to show up in listings),
            # so on "already exists" find that entry and update it instead.
            r = asc.s.post(API + path, json=payload, timeout=30)
            if r.status_code == 409 and "already exists" in r.text:
                attrs = dict(payload["data"]["attributes"])
                locale = attrs.pop("locale")
                existing = None
                for _ in range(10):
                    existing = {l["attributes"]["locale"]: l for l in
                                asc.get_all(f"/appInfos/{info_id}/appInfoLocalizations")}.get(locale)
                    if existing:
                        break
                    time.sleep(2)
                if not existing:
                    sys.exit(f"{locale}: App Information entry exists but can't be found yet. "
                             f"Wait a minute and re-run — finished languages are skipped.")
                method, path = "PATCH", f"/appInfoLocalizations/{existing['id']}"
                asc.call(method, path, json={"data": {"type": "appInfoLocalizations",
                                                      "id": existing["id"], "attributes": attrs}})
            elif r.status_code >= 400:
                sys.exit(f"POST {path} failed: HTTP {r.status_code}\n{r.text}")
            print(f"  wrote {i}/{len(actions)}: {method} {path}")
            continue
        asc.call(method, path, json=payload)
        print(f"  wrote {i}/{len(actions)}: {method} {path}")
    print(f"\nDone: {len(actions)} change(s) written. Review the version page in App Store Connect.")


if __name__ == "__main__":
    main()
