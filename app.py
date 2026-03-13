import streamlit as st
import cv2
import os
import numpy as np
import time
import random

st.title("Deteksi Wajah & Pengolahan Citra")

# =============================
# FACE DETECTOR
# =============================
def detect_faces(image):

    face_cascade = cv2.CascadeClassifier(
        cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
    )

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

    faces = face_cascade.detectMultiScale(
        gray,
        scaleFactor=1.1,
        minNeighbors=5,
        minSize=(30,30)
    )

    return faces


# =============================
# SALT PEPPER NOISE
# =============================
def add_salt_pepper_noise(image, prob=0.02):

    noisy = image.copy()
    h, w, c = noisy.shape

    for i in range(h):
        for j in range(w):

            r = random.random()

            if r < prob:
                noisy[i][j] = 0
            elif r > 1-prob:
                noisy[i][j] = 255

    return noisy


# =============================
# REMOVE NOISE
# =============================
def remove_noise(image):

    return cv2.medianBlur(image,5)


# =============================
# SHARPEN IMAGE
# =============================
def sharpen_image(image):

    kernel = np.array([
        [0,-1,0],
        [-1,5,-1],
        [0,-1,0]
    ])

    return cv2.filter2D(image,-1,kernel)


# =============================
# PROCESS DATASET
# =============================
def process_dataset(do_noise, do_denoise, do_sharpen, do_pipeline):

    dataset_path = "dataset"
    processed_path = "processed_dataset"

    os.makedirs(processed_path, exist_ok=True)

    for person in os.listdir(dataset_path):

        person_path = os.path.join(dataset_path, person)
        save_path = os.path.join(processed_path, person)

        os.makedirs(save_path, exist_ok=True)

        for img_name in os.listdir(person_path):

            img_path = os.path.join(person_path, img_name)
            image = cv2.imread(img_path)

            if do_noise:
                noisy = add_salt_pepper_noise(image)
                cv2.imwrite(
                    os.path.join(save_path,"noise_"+img_name),
                    noisy
                )

            if do_denoise:
                denoise = remove_noise(image)
                cv2.imwrite(
                    os.path.join(save_path,"denoise_"+img_name),
                    denoise
                )

            if do_sharpen:
                sharpen = sharpen_image(image)
                cv2.imwrite(
                    os.path.join(save_path,"sharpen_"+img_name),
                    sharpen
                )

            if do_pipeline:

                noisy = add_salt_pepper_noise(image)
                denoise = remove_noise(noisy)
                sharpen = sharpen_image(denoise)

                cv2.imwrite(
                    os.path.join(save_path,"pipeline_"+img_name),
                    sharpen
                )


# =============================
# PREVIEW IMAGE
# =============================
def preview_processing(do_noise, do_denoise, do_sharpen, do_pipeline):

    dataset_path = "dataset"

    persons = os.listdir(dataset_path)

    if len(persons) == 0:
        st.warning("Dataset kosong")
        return

    person = persons[0]
    person_path = os.path.join(dataset_path, person)

    images = os.listdir(person_path)

    if len(images) == 0:
        st.warning("Tidak ada gambar")
        return

    img_path = os.path.join(person_path, images[0])

    image = cv2.imread(img_path)

    image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)

    st.subheader("Preview Hasil Pengolahan")

    cols = st.columns(5)

    cols[0].image(image_rgb, caption="Original")

    if do_noise:

        noisy = add_salt_pepper_noise(image)

        cols[1].image(
            cv2.cvtColor(noisy,cv2.COLOR_BGR2RGB),
            caption="Noise"
        )

    if do_denoise:

        denoise = remove_noise(image)

        cols[2].image(
            cv2.cvtColor(denoise,cv2.COLOR_BGR2RGB),
            caption="Denoise"
        )

    if do_sharpen:

        sharpen = sharpen_image(image)

        cols[3].image(
            cv2.cvtColor(sharpen,cv2.COLOR_BGR2RGB),
            caption="Sharpen"
        )

    if do_pipeline:

        noisy = add_salt_pepper_noise(image)
        denoise = remove_noise(noisy)
        sharpen = sharpen_image(denoise)

        cols[4].image(
            cv2.cvtColor(sharpen,cv2.COLOR_BGR2RGB),
            caption="Pipeline"
        )


# =============================
# CAPTURE DATASET
# =============================
st.header("Tambah Dataset Wajah")

name = st.text_input("Nama orang")

capture = st.button("Ambil Dataset")

if capture:

    if name == "":
        st.warning("Masukkan nama terlebih dahulu")

    else:

        save_path = os.path.join("dataset",name)

        os.makedirs(save_path,exist_ok=True)

        cap = cv2.VideoCapture(0)

        st.info("Mengambil 20 gambar wajah")

        frame_placeholder = st.empty()

        count = 0

        while count < 20:

            ret,frame = cap.read()

            if not ret:
                break

            faces = detect_faces(frame)

            for (x,y,w,h) in faces:

                face = frame[y:y+h,x:x+w]

                file_name = os.path.join(
                    save_path,
                    f"img_{count}.jpg"
                )

                cv2.imwrite(file_name,face)

                count += 1

                cv2.rectangle(
                    frame,
                    (x,y),
                    (x+w,y+h),
                    (0,255,0),
                    2
                )

                break

            frame_rgb = cv2.cvtColor(frame,cv2.COLOR_BGR2RGB)

            frame_placeholder.image(frame_rgb)

            time.sleep(0.1)

        cap.release()

        st.success("Dataset berhasil dibuat")


# =============================
# IMAGE PROCESSING
# =============================
st.header("Pengolahan Citra")

salt_pepper = st.checkbox("Salt & Pepper Noise")

remove_noise_option = st.checkbox("Remove Noise")

sharpen_option = st.checkbox("Sharpening")

pipeline_option = st.checkbox("Pipeline (Noise → Denoise → Sharpen)")


process = st.button("Proses Pengolahan")

if process:

    if not (salt_pepper or remove_noise_option or sharpen_option or pipeline_option):

        st.warning("Pilih minimal satu pengolahan")

    else:

        process_dataset(
            salt_pepper,
            remove_noise_option,
            sharpen_option,
            pipeline_option
        )

        st.success("Pengolahan selesai")

        preview_processing(
            salt_pepper,
            remove_noise_option,
            sharpen_option,
            pipeline_option
        )