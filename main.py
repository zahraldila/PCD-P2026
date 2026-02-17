import os
from uuid import uuid4
from fastapi import FastAPI, File, UploadFile, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
import numpy as np
import cv2

app = FastAPI()

# Mount folder static
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

# Pastikan folder upload ada
if not os.path.exists("static/uploads"):
    os.makedirs("static/uploads")


@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    return templates.TemplateResponse("home.html", {"request": request})


@app.post("/upload/", response_class=HTMLResponse)
async def upload_image(request: Request, file: UploadFile = File(...)):
    image_data = await file.read()

    # Buat nama file unik
    file_extension = file.filename.split(".")[-1]
    filename = f"{uuid4()}.{file_extension}"
    file_path = os.path.join("static", "uploads", filename)

    # Simpan file
    with open(file_path, "wb") as f:
        f.write(image_data)

    # Ubah jadi array numpy
    np_array = np.frombuffer(image_data, np.uint8)

    # Decode gambar
    img = cv2.imdecode(np_array, cv2.IMREAD_COLOR)

    # Split channel (OpenCV default = BGR)
    b, g, r = cv2.split(img)

    # Convert ke list supaya bisa tampil di HTML
    rgb_array = {
        "R": r.tolist(),
        "G": g.tolist(),
        "B": b.tolist()
    }

    return templates.TemplateResponse("display.html", {
        "request": request,
        "image_path": f"/static/uploads/{filename}",
        "rgb_array": rgb_array
    })
