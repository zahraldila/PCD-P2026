import os
from uuid import uuid4

from fastapi import FastAPI, File, UploadFile, Request, Form
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
from skimage.exposure import match_histograms
from skimage.metrics import structural_similarity as ssim

import numpy as np
import cv2
import matplotlib.pyplot as plt

app = FastAPI()

app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

os.makedirs("static/uploads", exist_ok=True)
os.makedirs("static/histograms", exist_ok=True)
os.makedirs("static/charts", exist_ok=True)
os.makedirs("static/compressed", exist_ok=True)


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
# Utility Functions Modul 6 - Kompresi Citra
# =========================
def save_uploaded_original_file(file_bytes: bytes, original_filename: str):
    """
    Menyimpan file asli hasil upload agar ukuran file asli tetap sesuai
    dengan file yang diunggah, bukan hasil encode ulang OpenCV.
    """
    ext = os.path.splitext(original_filename)[1].lower()

    if ext not in [".jpg", ".jpeg", ".png", ".bmp", ".tif", ".tiff"]:
        ext = ".png"

    filename = f"original_{uuid4()}{ext}"
    path = os.path.join("static/compressed", filename)

    with open(path, "wb") as f:
        f.write(file_bytes)

    return path, f"/static/compressed/{filename}"


def save_compressed_image(image, method: str, jpeg_quality: int = 75, png_level: int = 9):
    """
    Menyimpan citra hasil kompresi berdasarkan metode yang dipilih.
    JPEG menggunakan quality 0-100.
    PNG menggunakan compression level 0-9.
    """
    method = method.lower()

    if method == "jpeg":
        filename = f"compressed_jpeg_q{jpeg_quality}_{uuid4()}.jpg"
        path = os.path.join("static/compressed", filename)
        cv2.imwrite(path, image, [cv2.IMWRITE_JPEG_QUALITY, int(jpeg_quality)])

    elif method == "png":
        filename = f"compressed_png_l{png_level}_{uuid4()}.png"
        path = os.path.join("static/compressed", filename)
        cv2.imwrite(path, image, [cv2.IMWRITE_PNG_COMPRESSION, int(png_level)])

    else:
        raise ValueError("Metode kompresi tidak valid.")

    return path, f"/static/compressed/{filename}"


def load_compressed_image(path):
    """
    Membaca ulang citra hasil kompresi.
    PSNR dan SSIM dihitung dari citra yang sudah benar-benar dikompresi.
    """
    return cv2.imread(path, cv2.IMREAD_COLOR)


def calculate_compression_metrics(original_img, compressed_img, original_size, compressed_size):
    """
    Menghitung compression ratio, PSNR, SSIM, dan status identik.
    """
    if original_img is None or compressed_img is None:
        return {
            "compression_ratio": "0.00",
            "psnr": "Error",
            "ssim": "Error",
            "identical": "Tidak"
        }

    if original_img.shape != compressed_img.shape:
        compressed_img = cv2.resize(
            compressed_img,
            (original_img.shape[1], original_img.shape[0])
        )

    compression_ratio = original_size / compressed_size if compressed_size > 0 else 0

    psnr_value = cv2.PSNR(original_img, compressed_img)

    try:
        if len(original_img.shape) == 3:
            ssim_value = ssim(
                original_img,
                compressed_img,
                channel_axis=2,
                data_range=255
            )
        else:
            ssim_value = ssim(
                original_img,
                compressed_img,
                data_range=255
            )
    except Exception:
        ssim_value = None

    identical = np.array_equal(original_img, compressed_img)

    if psnr_value == float("inf"):
        psnr_display = "Infinity"
    else:
        psnr_display = f"{psnr_value:.2f}"

    if ssim_value is None:
        ssim_display = "Error"
    else:
        ssim_display = f"{ssim_value:.4f}"

    return {
        "compression_ratio": f"{compression_ratio:.2f}",
        "psnr": psnr_display,
        "ssim": ssim_display,
        "identical": "Ya" if identical else "Tidak"
    }


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
    return templates.TemplateResponse(
        request=request,
        name="home.html",
        context={"request": request}
    )


@app.post("/upload/", response_class=HTMLResponse)
async def upload_image(request: Request, file: UploadFile = File(...)):
    image_data = await file.read()
    img = decode_image(image_data, cv2.IMREAD_COLOR)

    if img is None:
        return HTMLResponse("Gagal membaca gambar.", status_code=400)

    file_path = save_image(img, "uploaded")

    return templates.TemplateResponse(
        request=request,
        name="result.html",
        context={
            "request": request,
            "original_image_path": file_path,
            "modified_image_path": file_path
        }
    )


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

    return templates.TemplateResponse(
        request=request,
        name="result.html",
        context={
            "request": request,
            "original_image_path": original_path,
            "modified_image_path": modified_path
        }
    )


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

    return templates.TemplateResponse(
        request=request,
        name="result.html",
        context={
            "request": request,
            "original_image_path": original_path,
            "modified_image_path": modified_path
        }
    )


@app.get("/grayscale/", response_class=HTMLResponse)
async def grayscale_form(request: Request):
    return templates.TemplateResponse(
        request=request,
        name="grayscale.html",
        context={"request": request}
    )


@app.post("/grayscale/", response_class=HTMLResponse)
async def convert_grayscale(request: Request, file: UploadFile = File(...)):
    image_data = await file.read()
    img = decode_image(image_data, cv2.IMREAD_COLOR)

    if img is None:
        return HTMLResponse("Gagal membaca gambar.", status_code=400)

    gray_img = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    original_path = save_image(img, "original")
    modified_path = save_image(gray_img, "grayscale")

    return templates.TemplateResponse(
        request=request,
        name="result.html",
        context={
            "request": request,
            "original_image_path": original_path,
            "modified_image_path": modified_path
        }
    )


@app.get("/histogram/", response_class=HTMLResponse)
async def histogram_form(request: Request):
    return templates.TemplateResponse(
        request=request,
        name="histogram.html",
        context={"request": request}
    )


@app.post("/histogram/", response_class=HTMLResponse)
async def generate_histogram(request: Request, file: UploadFile = File(...)):
    image_data = await file.read()
    img = decode_image(image_data, cv2.IMREAD_COLOR)

    if img is None:
        return HTMLResponse("Tidak dapat membaca gambar yang diunggah.", status_code=400)

    gray_img = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    grayscale_histogram_path = save_histogram(gray_img, "grayscale")
    color_histogram_path = save_color_histogram(img)

    return templates.TemplateResponse(
        request=request,
        name="histogram.html",
        context={
            "request": request,
            "grayscale_histogram_path": grayscale_histogram_path,
            "color_histogram_path": color_histogram_path
        }
    )


@app.get("/equalize/", response_class=HTMLResponse)
async def equalize_form(request: Request):
    return templates.TemplateResponse(
        request=request,
        name="equalize.html",
        context={"request": request}
    )


@app.post("/equalize/", response_class=HTMLResponse)
async def equalize_histogram(request: Request, file: UploadFile = File(...)):
    image_data = await file.read()
    img = decode_image(image_data, cv2.IMREAD_GRAYSCALE)

    if img is None:
        return HTMLResponse("Gagal membaca gambar grayscale.", status_code=400)

    equalized_img = cv2.equalizeHist(img)

    original_path = save_image(img, "original")
    modified_path = save_image(equalized_img, "equalized")

    return templates.TemplateResponse(
        request=request,
        name="result.html",
        context={
            "request": request,
            "original_image_path": original_path,
            "modified_image_path": modified_path
        }
    )


@app.get("/specify/", response_class=HTMLResponse)
async def specify_form(request: Request):
    return templates.TemplateResponse(
        request=request,
        name="specify.html",
        context={"request": request}
    )


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

    return templates.TemplateResponse(
        request=request,
        name="result.html",
        context={
            "request": request,
            "original_image_path": original_path,
            "modified_image_path": modified_path
        }
    )


@app.get("/statistics/", response_class=HTMLResponse)
async def statistics_form(request: Request):
    return templates.TemplateResponse(
        request=request,
        name="statistics.html",
        context={"request": request}
    )


@app.post("/statistics/", response_class=HTMLResponse)
async def calculate_statistics(request: Request, file: UploadFile = File(...)):
    image_data = await file.read()
    img = decode_image(image_data, cv2.IMREAD_GRAYSCALE)

    if img is None:
        return HTMLResponse("Gagal membaca gambar grayscale.", status_code=400)

    mean_intensity = np.mean(img)
    std_deviation = np.std(img)

    image_path = save_image(img, "statistics")

    return templates.TemplateResponse(
        request=request,
        name="statistics.html",
        context={
            "request": request,
            "mean_intensity": mean_intensity,
            "std_deviation": std_deviation,
            "image_path": image_path
        }
    )


# =========================
# Route Modul 6: Kompresi Citra
# =========================
@app.get("/compression/", response_class=HTMLResponse)
async def compression_form(request: Request):
    return templates.TemplateResponse(
        request=request,
        name="compression.html",
        context={
            "request": request,
            "result": None
        }
    )


@app.post("/compression/", response_class=HTMLResponse)
async def compress_image(
    request: Request,
    file: UploadFile = File(...),
    method: str = Form(...),
    jpeg_quality: int = Form(75),
    png_level: int = Form(9)
):
    image_data = await file.read()
    img = decode_image(image_data, cv2.IMREAD_COLOR)

    if img is None:
        return HTMLResponse("Gagal membaca gambar yang diunggah.", status_code=400)

    method = method.lower()

    if method not in ["jpeg", "png"]:
        return HTMLResponse("Metode kompresi tidak valid.", status_code=400)

    jpeg_quality = max(0, min(100, int(jpeg_quality)))
    png_level = max(0, min(9, int(png_level)))

    original_file_path, original_url = save_uploaded_original_file(
        image_data,
        file.filename
    )

    original_size = os.path.getsize(original_file_path)

    compressed_file_path, compressed_url = save_compressed_image(
        img,
        method=method,
        jpeg_quality=jpeg_quality,
        png_level=png_level
    )

    compressed_size = os.path.getsize(compressed_file_path)
    compressed_img = load_compressed_image(compressed_file_path)

    metrics = calculate_compression_metrics(
        original_img=img,
        compressed_img=compressed_img,
        original_size=original_size,
        compressed_size=compressed_size
    )

    if method == "jpeg":
        parameter_label = f"Quality {jpeg_quality}"
        method_label = "JPEG (Lossy)"
        explanation = (
            "JPEG merupakan kompresi lossy, sehingga ukuran file dapat menjadi lebih kecil, "
            "tetapi sebagian informasi citra dapat hilang. Semakin rendah quality, ukuran file "
            "biasanya semakin kecil, namun kualitas visual dan nilai PSNR/SSIM dapat menurun."
        )
    else:
        parameter_label = f"Compression Level {png_level}"
        method_label = "PNG (Lossless)"
        explanation = (
            "PNG merupakan kompresi lossless, sehingga citra hasil kompresi idealnya tetap "
            "identik dengan citra asli. Nilai PSNR dapat menjadi Infinity dan SSIM mendekati "
            "atau sama dengan 1 apabila tidak ada perbedaan piksel."
        )

    result = {
        "filename": file.filename,
        "method": method_label,
        "parameter": parameter_label,
        "original_image_path": original_url,
        "compressed_image_path": compressed_url,
        "original_size_kb": f"{original_size / 1024:.2f}",
        "compressed_size_kb": f"{compressed_size / 1024:.2f}",
        "compression_ratio": metrics["compression_ratio"],
        "psnr": metrics["psnr"],
        "ssim": metrics["ssim"],
        "identical": metrics["identical"],
        "explanation": explanation
    }

    return templates.TemplateResponse(
        request=request,
        name="compression.html",
        context={
            "request": request,
            "result": result
        }
    )


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

    return templates.TemplateResponse(
        request=request,
        name="result.html",
        context={
            "request": request,
            "original_image_path": original_path,
            "modified_image_path": modified_path
        }
    )