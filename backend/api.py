from __future__ import annotations

import random
from fastapi import FastAPI


app = FastAPI(title="Race Savant API", version="0.1.0")

EMOJIS = [
    "😀",
    "😄",
    "🎉",
    "🚀",
    "🔥",
    "✨",
    "🥳",
    "🏎️",
    "💨",
    "🏁",
]


@app.get("/", summary="Hello test endpoint")
def hello():
    """Return a hello world with three random emojis."""
    # Choose 3 unique emojis for each response
    suffix = "".join(random.sample(EMOJIS, k=3))
    return {"message": f"Hello, world {suffix}"}


if __name__ == "__main__":
    # Run with: python api.py  (or `uvicorn api:app --reload`)
    import uvicorn

    uvicorn.run("api:app", host="0.0.0.0", port=8000, reload=True)

