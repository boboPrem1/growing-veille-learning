import base64
import hashlib
import hmac
import json
import time

SECRET = b"mon_secret_tres_long_et_aleatoire_256bits"

# ──────────────────────────────────────────────
# Helpers Base64URL (RFC 4648 §5)
# Base64URL = Base64 avec + → -, / → _, sans padding =
# ──────────────────────────────────────────────

# Function for encode bytes
def b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("utf-8")

# Function for decode the token
def b64url_decode(data: str) -> bytes:
    # add the deleted padding
    padding = 4 -len(data) % 4
    if padding != 4:
        data += "=" * padding
    return base64.urlsafe_b64decode(data)

# ──────────────────────────────────────────────
# Creating the token
# ──────────────────────────────────────────────

def create_jwt(payload: dict, secret: bytes) -> str:
    # 1- Header always the same for HS256
    header = {"alg": "HS256", "typ": "jwt"}
    
    # 2- Encode the header and the payload in base64url
    header_b64 = b64url_encode(json.dumps(header, separators=(",", ":")).encode())
    payload_b64 = b64url_encode(json.dumps(payload, separators=(",", ":")).encode())
    
    # 3- Getting the signing input = base64url(header) + "." + base64url(payload)
    signing_input = f"{header_b64}.{payload_b64}".encode("utf-8")
    
    # 4- Creating the HMAC-SHA256 Signature
    signature = hmac.new(secret, signing_input, hashlib.sha256).digest()
    signature_b64 = b64url_encode(signature)
    
    return f"{header_b64}.{payload_b64}.{signature_b64}"

# ──────────────────────────────────────────────
# Token verification (Without library)
# ──────────────────────────────────────────────
def verify_jwt(token: str, secret: bytes) -> dict:
    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError("Malformed token: Must have 3 parts splited by '.'")
    
    header_b64, payload_b64, signature_b64 = parts
    
    # 1- Let's verify the algorithm before any signature validation
    header = json.loads(b64url_decode(header_b64))
    if header.get("alg") != "HS256":
        raise ValueError(f"Algorithme not supported: {header.get('alg')}")
    
    # 2- Recalculate the HMAC signature
    signature_input = f"{header_b64}.{payload_b64}".encode("utf-8")
    expected_sig = hmac.new(secret, signature_input, hashlib.sha256).digest()
    
    # 3- Constant time comparison
    try:
        actual_sig = b64url_decode(signature_b64)
    except Exception:
        raise ValueError("Wrong encoded signature")
    
    if not hmac.compare_digest(expected_sig, actual_sig):
        raise ValueError("Invalid signature - falsified token or incorrect secret")
    
    # 4- Decoding the payload
    payload = json.loads(b64url_decode(payload_b64))
    
    # 5- Validate time-related claims
    now = int(time.time())
    
    if "exp" in payload and now > payload["exp"]:
        raise ValueError(f"Expired token since {now - payload['exp']} secondes")
    
    if "nbf" in payload and now < payload["nbf"]:
        raise ValueError(f"Token not valid yet (nbf) not reached")
    
    return payload

# ──────────────────────────────────────────────
# Démonstration
# ──────────────────────────────────────────────

if __name__ == "__main__":
    payload = {
        "sub": "user_42",
        "role": "editor",
        "iat": int(time.time()),
        "exp": int(time.time()) + 900, # 15 minutes
    }
    
    token = create_jwt(payload, SECRET)
    print(f"Token generated succefully: \n{token}\n")
    
    # Show decoded parts
    header_b64, payload_b64, signature_b64 = token.split(".")
    print(f"Header  : {json.loads(b64url_decode(header_b64))}")
    print(f"Payload : {json.loads(b64url_decode(payload_b64))}")
    print(f"Sig     : {signature_b64[:5]}...\n")
    
    # Token validity verification
    decoded = verify_jwt(token, SECRET)
    print(f"Verification Ok, Decoded token: {decoded}")
    
    # Falsification test, edit directly the decoded payload of the token
    tampered = f"{header_b64}.{b64url_encode(b'{"sub": "admin", "role": "superadmin"}')}.{signature_b64}"
    
    try:
        decoded_tampered = verify_jwt(tampered, SECRET)
    except ValueError as e:
        print(f"Token falsification detected : {e}")