#!/usr/bin/env python3
"""Signing for TestFlight builds on GitHub's Macs, without stored certificates.

  setup    Creates an Apple Distribution certificate and an App Store profile for each
           bundle ID through the App Store Connect API, puts them on this Mac, and switches
           project.yml to manual signing with them.
  cleanup  Deletes this run's profiles and revokes the certificate (builds already uploaded
           are unaffected: Apple re-signs TestFlight and App Store builds).

Needs ASC_KEY_ID, ASC_ISSUER_ID, KEY_PATH (the .p8) and RUNNER_TEMP. Never prints secrets.
Python packages: pyjwt, cryptography.
"""
import base64
import json
import os
import re
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_IDS = {
    "com.georgeodwyer.kinetix": "KX_PROFILE_APP",
    "com.georgeodwyer.kinetix.widgets": "KX_PROFILE_WIDGETS",
    "com.georgeodwyer.kinetix.watchkitapp": "KX_PROFILE_WATCH",
}
PROFILE_PREFIX = "Kinetix CI"
WORK = os.path.join(os.environ.get("RUNNER_TEMP", "/tmp"), "signing")
STATE = os.path.join(WORK, "state.json")


def token():
    import jwt  # pyjwt

    with open(os.environ["KEY_PATH"]) as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def api(method, path, body=None):
    url = path if path.startswith("http") else API + path
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise SystemExit(f"App Store Connect {method} {path.split('?')[0]} failed ({error.code}): {detail}")


def run(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True)


def github_env(name, value):
    path = os.environ.get("GITHUB_ENV")
    if path:
        with open(path, "a") as f:
            f.write(f"{name}={value}\n")


def make_key_and_csr():
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.x509.oid import NameOID

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = (x509.CertificateSigningRequestBuilder()
           .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, PROFILE_PREFIX),
                                    x509.NameAttribute(NameOID.COUNTRY_NAME, "GB")]))
           .sign(key, hashes.SHA256()))
    key_pem = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL,
                                serialization.NoEncryption())
    return key_pem, csr.public_bytes(serialization.Encoding.PEM).decode()


def install_keychain(key_pem, cert_der):
    keychain = os.path.join(WORK, "kinetix-ci.keychain-db")
    password = secrets.token_hex(16)
    key_path = os.path.join(WORK, "key.pem")
    cert_path = os.path.join(WORK, "cert.cer")
    with open(key_path, "wb") as f:
        f.write(key_pem)
    with open(cert_path, "wb") as f:
        f.write(cert_der)
    run("security", "create-keychain", "-p", password, keychain)
    run("security", "set-keychain-settings", "-lut", "21600", keychain)
    run("security", "unlock-keychain", "-p", password, keychain)
    run("security", "import", key_path, "-k", keychain, "-t", "priv", "-f", "openssl",
        "-T", "/usr/bin/codesign", "-T", "/usr/bin/security")
    run("security", "import", cert_path, "-k", keychain, "-t", "cert", "-f", "x509")
    # Apple's intermediate certificate, in case this Mac doesn't have it.
    wwdr = os.path.join(WORK, "AppleWWDRCAG3.cer")
    try:
        urllib.request.urlretrieve("https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer", wwdr)
        run("security", "import", wwdr, "-k", keychain, check=False)
    except Exception:
        pass
    run("security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", password, keychain)
    existing = [line.strip().strip('"') for line in run("security", "list-keychains", "-d", "user").stdout.splitlines()]
    run("security", "list-keychains", "-d", "user", "-s", keychain, *[k for k in existing if k])
    os.remove(key_path)
    return keychain


def install_profile(content_b64, uuid):
    data = base64.b64decode(content_b64)
    home = os.path.expanduser("~")
    for folder in ("Library/MobileDevice/Provisioning Profiles", "Library/Developer/Xcode/UserData/Provisioning Profiles"):
        path = os.path.join(home, folder)
        os.makedirs(path, exist_ok=True)
        with open(os.path.join(path, uuid + ".mobileprovision"), "wb") as f:
            f.write(data)


def switch_project_to_manual(profiles):
    """project.yml on this Mac only: manual signing with this run's profiles."""
    with open("project.yml") as f:
        lines = f.read().splitlines()
    out = []
    for line in lines:
        out.append(line)
        match = re.match(r"^(\s*)PRODUCT_BUNDLE_IDENTIFIER:\s*(\S+)\s*$", line)
        if match and match.group(2) in profiles:
            indent = match.group(1)
            out.append(f'{indent}PROVISIONING_PROFILE_SPECIFIER: "{profiles[match.group(2)]}"')
            out.append(f'{indent}CODE_SIGN_IDENTITY: "Apple Distribution"')
    text = "\n".join(out) + "\n"
    text = text.replace("CODE_SIGN_STYLE: Automatic", "CODE_SIGN_STYLE: Manual")
    with open("project.yml", "w") as f:
        f.write(text)


def setup():
    os.makedirs(WORK, exist_ok=True)
    run_id = os.environ.get("GITHUB_RUN_NUMBER", str(int(time.time())))
    state = {"certificate": None, "profiles": [], "keychain": None}

    key_pem, csr = make_key_and_csr()
    created = api("POST", "/certificates", {"data": {"type": "certificates", "attributes": {
        "certificateType": "DISTRIBUTION", "csrContent": csr}}})["data"]
    state["certificate"] = created["id"]
    save(state)
    print(f"Created distribution certificate {created['attributes'].get('serialNumber', '')}")
    state["keychain"] = install_keychain(key_pem, base64.b64decode(created["attributes"]["certificateContent"]))
    save(state)
    github_env("KX_KEYCHAIN", state["keychain"])

    names = {}
    for identifier, env_name in BUNDLE_IDS.items():
        found = api("GET", f"/bundleIds?filter[identifier]={identifier}&limit=200")["data"]
        bundle = next((b for b in found if b["attributes"]["identifier"] == identifier), None)
        if bundle is None:
            raise SystemExit(f"Bundle ID {identifier} isn't registered on developer.apple.com")
        # Old CI profiles for this ID (a run that was cancelled before cleanup).
        for old in api("GET", f"/bundleIds/{bundle['id']}/profiles?limit=200").get("data", []):
            if old["attributes"]["name"].startswith(PROFILE_PREFIX):
                api("DELETE", f"/profiles/{old['id']}")
        name = f"{PROFILE_PREFIX} {identifier.split('.')[-1]} {run_id}"
        profile = api("POST", "/profiles", {"data": {
            "type": "profiles",
            "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}},
                "certificates": {"data": [{"type": "certificates", "id": created["id"]}]},
            }}})["data"]
        state["profiles"].append(profile["id"])
        save(state)
        install_profile(profile["attributes"]["profileContent"], profile["attributes"]["uuid"])
        names[identifier] = name
        github_env(env_name, name)
        print(f"Created profile '{name}'")

    with open(os.path.join(WORK, "profiles.json"), "w") as f:
        json.dump(names, f)
    switch_project_to_manual(names)
    print("project.yml switched to manual signing for this build")


def cleanup():
    if not os.path.exists(STATE):
        print("Nothing to clean up")
        return
    with open(STATE) as f:
        state = json.load(f)
    for profile_id in state.get("profiles", []):
        try:
            api("DELETE", f"/profiles/{profile_id}")
        except SystemExit as error:
            print(f"::warning::{error}")
    if state.get("certificate"):
        try:
            api("DELETE", f"/certificates/{state['certificate']}")
            print("Revoked this build's distribution certificate")
        except SystemExit as error:
            print(f"::warning::{error}")
    if state.get("keychain"):
        run("security", "delete-keychain", state["keychain"], check=False)
    print(f"Removed {len(state.get('profiles', []))} profiles")


def save(state):
    with open(STATE, "w") as f:
        json.dump(state, f)


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "setup":
        setup()
    elif command == "cleanup":
        cleanup()
    else:
        raise SystemExit("usage: asc_signing.py setup|cleanup")
