import os
import json
from io import BytesIO
from typing import Optional, Any

try:
    from minio import Minio
    from minio.error import S3Error
    MINIO_AVAILABLE = True
except ImportError:
    MINIO_AVAILABLE = False
    Minio = None

class GCloudStorageService:
    """MinIO-backed object storage (drop-in replacement for GCS in self-hosted deployments)."""

    def __init__(self):
        self.bucket_name = os.getenv('GCLOUD_BUCKET_NAME', 'vibe-aiserver-data')
        endpoint      = os.getenv('MINIO_ENDPOINT', 'minio:9000')
        access_key    = os.getenv('MINIO_ACCESS_KEY', 'vibeadmin')
        secret_key    = os.getenv('MINIO_SECRET_KEY', 'change-this-strong-password')
        # Internal URL used by this server to build download links for subsequent pipeline steps.
        # Must be reachable from inside the Docker network.
        self.public_url = os.getenv('MINIO_PUBLIC_URL', f'http://{endpoint}')

        print(f"Storage initializing — endpoint: {endpoint}, bucket: {self.bucket_name}")

        self.client = None

        if not MINIO_AVAILABLE:
            print("MinIO library not installed — storage unavailable")
            return

        try:
            self.client = Minio(endpoint, access_key=access_key, secret_key=secret_key, secure=False)
            self._ensure_bucket()
            print("MinIO storage ready")
        except Exception as e:
            print(f"Error initializing MinIO client: {e}")
            self.client = None

    def _ensure_bucket(self):
        """Create the bucket and set public-read policy if it does not exist yet."""
        if self.client.bucket_exists(self.bucket_name):
            return
        self.client.make_bucket(self.bucket_name)
        # Allow anyone to read objects (so the AI server and browser can fetch files by URL).
        # Writes still require the access key / secret key.
        policy = json.dumps({
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"AWS": ["*"]},
                "Action": ["s3:GetObject"],
                "Resource": [f"arn:aws:s3:::{self.bucket_name}/*"]
            }]
        })
        self.client.set_bucket_policy(self.bucket_name, policy)
        print(f"Created bucket '{self.bucket_name}' with public-read policy")

    def _file_url(self, object_name: str) -> str:
        return f"{self.public_url}/{self.bucket_name}/{object_name}"

    async def upload_file(self, file_path: str, destination_name: str, content_type: str = 'application/octet-stream') -> Optional[str]:
        print(f"upload_file: {file_path} → {destination_name}")
        if not self.client:
            print("MinIO client not available")
            return None
        if not os.path.exists(file_path):
            print(f"File not found: {file_path}")
            return None
        try:
            self.client.fput_object(self.bucket_name, destination_name, file_path, content_type=content_type)
            url = self._file_url(destination_name)
            print(f"Uploaded to MinIO: {url}")
            return url
        except Exception as e:
            print(f"Error uploading file to MinIO: {e}")
            return None

    async def upload_text_content(self, content: str, destination_name: str, content_type: str = 'text/plain') -> Optional[str]:
        if not self.client:
            return None
        try:
            data = content.encode('utf-8')
            self.client.put_object(self.bucket_name, destination_name, BytesIO(data), len(data), content_type=content_type)
            return self._file_url(destination_name)
        except Exception as e:
            print(f"Error uploading content to MinIO: {e}")
            return None

    async def upload_json_content(self, data: Any, destination_name: str) -> Optional[str]:
        return await self.upload_text_content(json.dumps(data), destination_name, 'application/json')

    def get_file_url(self, file_name: str) -> str:
        return self._file_url(file_name)

    async def delete_job_files(self, job_id: str, prefixes: list = None) -> None:
        """Delete intermediate audio and transcript files after question generation completes."""
        if not self.client:
            return
        if prefixes is None:
            prefixes = [f"audio/{job_id}_", f"transcripts/{job_id}_"]
        deleted = 0
        for prefix in prefixes:
            try:
                objects = list(self.client.list_objects(self.bucket_name, prefix=prefix))
                for obj in objects:
                    self.client.remove_object(self.bucket_name, obj.object_name)
                    deleted += 1
                    print(f"Deleted MinIO object: {obj.object_name}", flush=True)
            except Exception as e:
                print(f"Error deleting MinIO objects with prefix '{prefix}': {e}", flush=True)
        if deleted:
            print(f"Cleanup: deleted {deleted} intermediate file(s) for job {job_id}", flush=True)
