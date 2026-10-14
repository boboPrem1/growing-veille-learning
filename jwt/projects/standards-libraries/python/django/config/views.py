from rest_framework import status
from rest_framework.decorators import api_view
from rest_framework.response import Response
from datetime import datetime, timedelta, timezone
import json
import jwt
import uuid
import os

SECRET = os.environ["SECRET"]
REFRESH_SECRET = os.environ["REFRESH_SECRET"]

def generate_access_token(user_id: str, role: str) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user_id,
        "role": role,
        "iat": now,
        "exp": now + timedelta(minutes=15),
        "iss": "https://api.monapp.com",
        "aud": "monapp-client",
        "jti": str(uuid.uuid4())
    }
    
    return jwt.encode(payload, SECRET, algorithm="HS256")

def generate_refresh_token(user_id: str) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user_id,
        "type": "refresh",
        "iat": now,
        "exp": now + timedelta(minutes=15),
        "iss": "https://api.monapp.com",
        "aud": "monapp-client",
        "jti": str(uuid.uuid4())
    }
    
    return jwt.encode(payload, REFRESH_SECRET, algorithm="HS256")

def decode_jwt(token: str, secret: str) -> dict:
    return jwt.decode(
        token,
        secret,
        algorithms=["HS256"],
        issuer="https://api.monapp.com",
        audience="monapp-client",
        leeway=30,
        options={
            "verify_exp": True,
            "verify_iat": True,
            "require": ["sub", "exp", "jti"]
        }
    )

@api_view(["GET"])
def index_view(request):
    access_token = generate_access_token("user_1234", "editor")
    refresh_token = generate_access_token("user_1234", "editor")
    
    tokens = {
        "access_token": access_token,
        "refresh_token": refresh_token
    }
    
    payload = decode_jwt(access_token, SECRET)
    refresh_payload = decode_jwt(refresh_token, SECRET)
    
    data = {
        "tokens": tokens,
        "payload": payload,
        "refresh_payload": refresh_payload
    }
    
    return Response(data=data, status=status.HTTP_200_OK)