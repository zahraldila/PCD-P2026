import os
from uuid import uuid4
from fastapi import FastAPI, File, UploadFile, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
import numpy as np
import cv2

import matplotlib
matplotlib.use("Agg")  # backend aman untuk server (tanpa GUI)
import matplotlib.pyplot as plt

app = FastAPI()

app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

UPLOAD_DIR = "static/uploads"
CHART_DIR = "static/charts"

os.makedirs(UPLOAD_DIR, exist_ok=True)
os.makedirs(CHART_DIR, exist_ok=True)


@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    return templates.TemplateResponse("home.html", {"request": request})


def save_rgb_histogram(r: np.ndarray, g: np.ndarray, b: np.ndarray, out_path: str) -> None:
    """Simpan histogram RGB sebagai gambar PNG."""
    plt.figure()
    plt.hist(r.ravel(), bins=256, alpha=0.5, label="R")
    plt.hist(g.ravel(), bins=256, alpha=0.5, label="G")
    plt.hist(b.ravel(), bins=256, alpha=0.5, label="B")
    plt.title("Histogram Intensitas RGB")
    plt.xlabel("Nilai Intensitas (0-255)")
    plt.ylabel("Frekuensi")
    plt.legend()
    plt.tight_layout()
    plt.savefig(out_path)
    plt.close()


@app.post("/upload/", response_class=HTMLResponse)
async def upload_image(request: Request, file: UploadFile = File(...)):
    image_data = await file.read()

    file_extension = file.filename.split(".")[-1]
    filename = f"{uuid4()}.{file_extension}"
    file_path = os.path.join(UPLOAD_DIR, filename)

    with open(file_path, "wb") as f:
        f.write(image_data)

    np_array = np.frombuffer(image_data, np.uint8)
    img = cv2.imdecode(np_array, cv2.IMREAD_COLOR)

    # Split channel (BGR -> b,g,r)
    b, g, r = cv2.split(img)

    # Array penuh (kalau mau tetap ditampilkan)
    rgb_array = {"R": r.tolist(), "G": g.tolist(), "B": b.tolist()}

    # ✅ Matriks kecil 10x10 (pojok kiri atas) biar jelas seperti matriks pixel
    h, w = r.shape
    n = 10
    n_h = min(n, h)
    n_w = min(n, w)

    rgb_matrix = {
        "R": r[:n_h, :n_w].tolist(),
        "G": g[:n_h, :n_w].tolist(),
        "B": b[:n_h, :n_w].tolist(),
    }

    # ✅ Buat chart histogram
    chart_name = f"{uuid4()}.png"
    chart_path = os.path.join(CHART_DIR, chart_name)
    save_rgb_histogram(r, g, b, chart_path)

    return templates.TemplateResponse(
        "display.html",
        {
            "request": request,
            "image_path": f"/static/uploads/{filename}",
            "rgb_array": rgb_array,
            "rgb_matrix": rgb_matrix,
            "hist_path": f"/static/charts/{chart_name}",
            "img_shape": {"height": int(h), "width": int(w)},
        },
    )
