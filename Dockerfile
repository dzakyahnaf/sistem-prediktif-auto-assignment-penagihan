FROM ubuntu:24.04 AS flutter-build
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils libglu1-mesa && rm -rf /var/lib/apt/lists/*
ARG FLUTTER_VERSION=3.41.6
ENV CI=true
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git /opt/flutter
ENV PATH=/opt/flutter/bin:$PATH
RUN flutter config --no-analytics && flutter precache --web
WORKDIR /frontend
COPY apps/assignment/pubspec.yaml apps/assignment/pubspec.lock ./
RUN flutter pub get --enforce-lockfile
COPY apps/assignment/lib ./lib
COPY apps/assignment/web ./web
RUN flutter build web --release --no-pub --no-wasm-dry-run --no-web-resources-cdn --dart-define=API_URL= --dart-define=PUBLIC_DEMO=true

FROM python:3.12-slim-bookworm AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends libgomp1 && rm -rf /var/lib/apt/lists/*
WORKDIR /app/backend
COPY backend/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir --require-hashes -r requirements.txt
COPY backend/app ./app
COPY backend/migrations ./migrations
COPY backend/alembic.ini ./alembic.ini
COPY deploy/start.py /app/start.py
COPY --from=flutter-build /frontend/build/web /app/web
RUN useradd --create-home --uid 10001 assignment
USER assignment
ENV WEB_BUILD_PATH=/app/web PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
EXPOSE 10000
CMD ["python", "/app/start.py"]
