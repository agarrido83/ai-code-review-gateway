import os

import httpx
from fastapi import FastAPI, HTTPException
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel

LITELLM_URL = os.environ["LITELLM_URL"]
LITELLM_API_KEY = os.environ["LITELLM_API_KEY"]
LITELLM_MODEL = os.getenv("LITELLM_MODEL", "claude-sonnet")

app = FastAPI(title="AI Code Review API")
Instrumentator().instrument(app).expose(app)


class ReviewRequest(BaseModel):
    code: str
    language: str


class ReviewResponse(BaseModel):
    suggestions: str


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/review", response_model=ReviewResponse)
async def review(request: ReviewRequest):
    prompt = (
        f"Review the following {request.language} code and provide concise suggestions "
        f"for improvement. Focus on correctness, readability, and best practices.\n\n"
        f"```{request.language}\n{request.code}\n```"
    )

    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                f"{LITELLM_URL}/chat/completions",
                headers={"Authorization": f"Bearer {LITELLM_API_KEY}"},
                json={
                    "model": LITELLM_MODEL,
                    "messages": [{"role": "user", "content": prompt}],
                },
            )
    except httpx.RequestError as e:
        raise HTTPException(status_code=503, detail=f"LiteLLM unavailable: {e}")

    if resp.status_code != 200:
        raise HTTPException(status_code=502, detail=f"LiteLLM error: {resp.text}")

    suggestions = resp.json()["choices"][0]["message"]["content"]
    return ReviewResponse(suggestions=suggestions)
