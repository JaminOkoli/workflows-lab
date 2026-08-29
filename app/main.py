from fastapi import FastAPI, HTTPException

app = FastAPI(title="workflows-lab")

ITEMS = {
    1: "first item",
    2: "second item",
}


@app.get("/")
def root():
    return {"message": "hello from workflows-lab"}


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/items/{item_id}")
def read_item(item_id: int):
    if item_id not in ITEMS:
        raise HTTPException(status_code=404, detail="item not found")
    return {"item_id": item_id, "name": ITEMS[item_id]}
