import os
from uuid import uuid4

from fastapi import FastAPI, File, UploadFile, Request, Form
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
from skimage.exposure import match_histograms

import numpy as np
import cv2
import matplotlib.pyplot as plt

app = FastAPI()

app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

os.makedirs("static/uploads", exist_ok=True)
os.makedirs("static/histograms", exist_ok=True)
os.makedirs("static/charts", exist_ok=True)


# =========================
# Utility Functions
# =========================
def decode_image(image_data: bytes, flag=cv2.IMREAD_COLOR):
    np_array = np.frombuffer(image_data, np.uint8)
    img = cv2.imdecode(np_array, flag)
    return img


def save_image(image, prefix):
    filename = f"{prefix}_{uuid4()}.png"
    path = os.path.join("static/uploads", filename)
    cv2.imwrite(path, image)
    return f"/static/uploads/{filename}"


def save_chart_image(image, prefix):
    filename = f"{prefix}_{uuid4()}.png"
    path = os.path.join("static/charts", filename)
    cv2.imwrite(path, image)
    return f"/static/charts/{filename}"


def save_histogram(image, prefix):
    histogram_path = f"static/histograms/{prefix}_{uuid4()}.png"
    plt.figure()
    plt.hist(image.ravel(), 256, [0, 256])
    plt.savefig(histogram_path)
    plt.close()
    return f"/{histogram_path}"


def save_color_histogram(image):
    color_histogram_path = f"static/histograms/color_{uuid4()}.png"
    plt.figure()
    for i, color in enumerate(["b", "g", "r"]):
        hist = cv2.calcHist([image], [i], None, [256], [0, 256])
        plt.plot(hist, color=color)
    plt.savefig(color_histogram_path)
    plt.close()
    return f"/{color_histogram_path}"


# =========================
# Functions from Colab
# =========================
def apply_convolution(image, kernel_type="average"):
    if kernel_type == "average":
        kernel = np.ones((3, 3), np.float32) / 9
    elif kernel_type == "sharpen":
        kernel = np.array([
            [0, -1, 0],
            [-1, 5, -1],
            [0, -1, 0]
        ])
    elif kernel_type == "edge":
        kernel = np.array([
            [-1, -1, -1],
            [-1, 8, -1],
            [-1, -1, -1]
        ])
    else:
        kernel = np.ones((3, 3), np.float32) / 9

    return cv2.filter2D(image, -1, kernel)


def apply_zero_padding(image, padding_size=10):
    return cv2.copyMakeBorder(
        image,
        padding_size, padding_size, padding_size, padding_size,
        cv2.BORDER_CONSTANT,
        value=[0, 0, 0]
    )


def apply_filter(image, filter_type="low"):
    if filter_type == "low":
        return cv2.GaussianBlur(image, (5, 5), 0)
    elif filter_type == "high":
        kernel = np.array([
            [0, -1, 0],
            [-1, 5, -1],
            [0, -1, 0]
        ])
        return cv2.filter2D(image, -1, kernel)
    elif filter_type == "band":
        low_pass = cv2.GaussianBlur(image, (9, 9), 0)
        high_pass = image - low_pass
        return low_pass + high_pass

    return image


def apply_fourier_transform(image):
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    f = np.fft.fft2(gray)
    fshift = np.fft.fftshift(f)
    magnitude_spectrum = 20 * np.log(np.abs(fshift) + 1)
    magnitude_spectrum = np.clip(magnitude_spectrum, 0, 255).astype(np.uint8)
    return magnitude_spectrum


def reduce_periodic_noise(image):
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    f = np.fft.fft2(gray)
    fshift = np.fft.fftshift(f)

    rows, cols = gray.shape
    crow, ccol = rows // 2, cols // 2

    mask = np.ones((rows, cols), np.uint8)
    r = 30
    mask[crow - r:crow + r, ccol - r:ccol + r] = 0

    fshift = fshift * mask
    f_ishift = np.fft.ifftshift(fshift)
    img_back = np.fft.ifft2(f_ishift)
    img_back = np.abs(img_back)
    img_back = np.clip(img_back, 0, 255).astype(np.uint8)

    return img_back


# =========================
# Routes
# =========================
@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    return templates.TemplateResponse("home.html", {"request": request})


@app.post("/upload/", response_class=HTMLResponse)
async def upload_image(request: Request, file: UploadFile = File(...)):
    image_data = await file.read()
    img = decode_image(image_data, cv2.IMREAD_COLOR)

    if img is None:
        return HTMLResponse("Gagal membaca gambar.", status_code=400)

    file_path = save_image(img, "uploaded")

    return templates.TemplateResponse("result.html", {
        "request": request,
        "original_image_path": file_path,
        "modified_image_path": file_path
    })


@app.post("/operation/", response_class=HTMLResponse)
async def perform_operation(
    request: Request,
    file: UploadFile = File(...),
    operation: str = Form(...),
    value: int = Form(...)
):
    image_data = await file.read()
    img = decode_image(image_data, cv2.IMREAD_COLOR)

    if img is None:
        return HTMLResponse("Gagal membaca gambar.", status_code=400)

    original_path = save_image(img, "original")

    if operation == "add":
        result_img = cv2.add(img, np.full(img.shape, value, dtype=np.uint8))
    elif operation == "subtract":
        result_img = cv2.subtract(img, np.full(img.shape, value, dtype=np.uint8))
    elif operation == "max":
        result_img = np.maximum(img, np.full(img.shape, value, dtype=np.uint8))
    elif operation == "min":
        result_img = np.minimum(img, np.full(img.shape, value, dtype=np.uint8))
    elif operation == "inverse":
        result_img = cv2.bitwise_not(img)
    else:
        return HTMLResponse("Operasi tidak valid.", status_code=400)

    modified_path = save_image(result_img, "modified")

    return templates.TemplateResponse("result.html", {
        "request": request,
        "original_image_path": original_path,
        "modified_image_path": modified_path
    })


@app.post("/logic_operation/", response_class=HTMLResponse)
async def perform_logic_operation(
    request: Request,
    file1: UploadFile = File(...),
    file2: UploadFile = File(None),
    operation: str = Form(...)
):
    image_data1 = await file1.read()
    img1 = decode_image(image_data1, cv2.IMREAD_COLOR)

    if img1 is None:
        return HTMLResponse("Gagal membaca gambar pertama.", status_code=400)

    original_path = save_image(img1, "original")

    if operation == "not":
        result_img = cv2.bitwise_not(img1)
    else:
        if file2 is None:
            return HTMLResponse("Operasi AND dan XOR memerlukan dua gambar.", status_code=400)

        image_data2 = await file2.read()
        img2 = decode_image(image_data2, cv2.IMREAD_COLOR)

        if img2 is None:
            return HTMLResponse("Gagal membaca gambar kedua.", status_code=400)

        if img1.shape != img2.shape:
            img2 = cv2.resize(img2, (img1.shape[1], img1.shape[0]))

        if operation == "and":
            result_img = cv2.bitwise_and(img1, img2)
        elif operation == "xor":
            result_img = cv2.bitwise_xor(img1, img2)
        else:
            return HTMLResponse("Operasi logika tidak valid.", status_code=400)

    modified_path = save_image(result_img, "modified")

    return templates.TemplateResponse("result.html", {
        "request": request,
        "original_image_path": original_path,
        "modified_image_path": modified_path
    })


@app.get("/grayscale/", response_class=HTMLResponse)
async def grayscale_form(request: Request):
    return templates.TemplateResponse("grayscale.html", {"request": request})


@app.post("/grayscale/", response_class=HTMLResponse)
async def convert_grayscale(request: Request, file: UploadFile = File(...)):
    image_data = await file.read()
    img = decode_image(image_data, cv2.IMREAD_COLOR)

    if img is None:
        return HTMLResponse("Gagal membaca gambar.", status_code=400)

    gray_img = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    original_path = save_image(img, "original")
    modified_path = save_image(gray_img, "grayscale")

    return templates.TemplateResponse("result.html", {
        "request": request,
        "original_image_path": original_path,
        "modified_image_path": modified_path
    })


@app.get("/histogram/", response_class=HTMLResponse)
async def histogram_form(request: Request):
    return templates.TemplateResponse("histogram.html", {"request": request})


@app.post("/histogram/", response_class=HTMLResponse)
async def generate_histogram(request: Request, file: UploadFile = File(...)):
    image_data = await file.read()
    img = decode_image(image_data, cv2.IMREAD_COLOR)

    if img is None:
        return HTMLResponse("Tidak dapat membaca gambar yang diunggah.", status_code=400)

    gray_img = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    grayscale_histogram_path = save_histogram(gray_img, "grayscale")
    color_histogram_path = save_color_histogram(img)

    return templates.TemplateResponse("histogram.html", {
        "request": request,
        "grayscale_histogram_path": grayscale_histogram_path,
        "color_histogram_path": color_histogram_path
    })


@app.get("/equalize/", response_class=HTMLResponse)
async def equalize_form(request: Request):
    return templates.TemplateResponse("equalize.html", {"request": request})


@app.post("/equalize/", response_class=HTMLResponse)
async def equalize_histogram(request: Request, file: UploadFile = File(...)):
    image_data = await file.read()
    img = decode_image(image_data, cv2.IMREAD_GRAYSCALE)

    if img is None:
        return HTMLResponse("Gagal membaca gambar grayscale.", status_code=400)

    equalized_img = cv2.equalizeHist(img)

    original_path = save_image(img, "original")
    modified_path = save_image(equalized_img, "equalized")

    return templates.TemplateResponse("result.html", {
        "request": request,
        "original_image_path": original_path,
        "modified_image_path": modified_path
    })


@app.get("/specify/", response_class=HTMLResponse)
async def specify_form(request: Request):
    return templates.TemplateResponse("specify.html", {"request": request})


@app.post("/specify/", response_class=HTMLResponse)
async def specify_histogram(
    request: Request,
    file: UploadFile = File(...),
    ref_file: UploadFile = File(...)
):
    image_data = await file.read()
    ref_image_data = await ref_file.read()

    img = decode_image(image_data, cv2.IMREAD_COLOR)
    ref_img = decode_image(ref_image_data, cv2.IMREAD_COLOR)

    if img is None or ref_img is None:
        return HTMLResponse("Gambar utama atau referensi tidak dapat dibaca.", status_code=400)

    specified_img = match_histograms(img, ref_img, channel_axis=-1)
    specified_img = np.clip(specified_img, 0, 255).astype("uint8")

    original_path = save_image(img, "original")
    modified_path = save_image(specified_img, "specified")

    return templates.TemplateResponse("result.html", {
        "request": request,
        "original_image_path": original_path,
        "modified_image_path": modified_path
    })


@app.get("/statistics/", response_class=HTMLResponse)
async def statistics_form(request: Request):
    return templates.TemplateResponse("statistics.html", {"request": request})


@app.post("/statistics/", response_class=HTMLResponse)
async def calculate_statistics(request: Request, file: UploadFile = File(...)):
    image_data = await file.read()
    img = decode_image(image_data, cv2.IMREAD_GRAYSCALE)

    if img is None:
        return HTMLResponse("Gagal membaca gambar grayscale.", status_code=400)

    mean_intensity = np.mean(img)
    std_deviation = np.std(img)

    image_path = save_image(img, "statistics")

    return templates.TemplateResponse("statistics.html", {
        "request": request,
        "mean_intensity": mean_intensity,
        "std_deviation": std_deviation,
        "image_path": image_path
    })


# =========================
# New Route: Colab Operations
# =========================
@app.post("/colab_operation/", response_class=HTMLResponse)
async def colab_operation(
    request: Request,
    file: UploadFile = File(...),
    operation: str = Form(...),
    kernel_type: str = Form("average"),
    filter_type: str = Form("low"),
    padding_size: int = Form(20)
):
    image_data = await file.read()
    img = decode_image(image_data, cv2.IMREAD_COLOR)

    if img is None:
        return HTMLResponse("Gambar tidak valid.", status_code=400)

    original_path = save_image(img, "original")

    if operation == "convolution":
        result_img = apply_convolution(img, kernel_type)
    elif operation == "padding":
        result_img = apply_zero_padding(img, padding_size)
    elif operation == "filter":
        result_img = apply_filter(img, filter_type)
    elif operation == "fourier":
        result_img = apply_fourier_transform(img)
    elif operation == "periodic_noise":
        result_img = reduce_periodic_noise(img)
    else:
        return HTMLResponse("Operasi Colab tidak dikenali.", status_code=400)

    modified_path = save_chart_image(result_img, operation)

    return templates.TemplateResponse("result.html", {
        "request": request,
        "original_image_path": original_path,
        "modified_image_path": modified_path
    })