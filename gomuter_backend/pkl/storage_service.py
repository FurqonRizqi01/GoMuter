import mimetypes
import os
from urllib import error, request
from urllib.parse import quote

from django.conf import settings


def is_supabase_storage_enabled() -> bool:
    return bool(
        settings.SUPABASE_URL
        and settings.SUPABASE_SERVICE_ROLE_KEY
        and settings.SUPABASE_STORAGE_BUCKET
    )


def upload_public_media(file_obj, folder: str, filename: str) -> str:
    """
    Upload media publik ke Supabase Storage.

    Dipakai untuk gambar produk/profil dan bukti DP agar file tidak bergantung
    pada filesystem Cloud Run yang bersifat ephemeral.
    """
    if not is_supabase_storage_enabled():
        raise RuntimeError('Supabase Storage belum dikonfigurasi.')

    safe_folder = folder.strip('/ ')
    safe_filename = os.path.basename(filename)
    object_path = f'{safe_folder}/{safe_filename}' if safe_folder else safe_filename
    encoded_path = '/'.join(quote(part) for part in object_path.split('/'))

    base_url = settings.SUPABASE_URL.rstrip('/')
    bucket = settings.SUPABASE_STORAGE_BUCKET
    upload_url = f'{base_url}/storage/v1/object/{bucket}/{encoded_path}'

    guessed_type = mimetypes.guess_type(safe_filename)[0]
    uploaded_type = getattr(file_obj, 'content_type', None)
    content_type = guessed_type or uploaded_type or 'application/octet-stream'
    if content_type == 'application/octet-stream' and uploaded_type:
        content_type = uploaded_type
    body = b''.join(file_obj.chunks()) if hasattr(file_obj, 'chunks') else file_obj.read()

    req = request.Request(
        upload_url,
        data=body,
        method='POST',
        headers={
            'Authorization': f'Bearer {settings.SUPABASE_SERVICE_ROLE_KEY}',
            'apikey': settings.SUPABASE_SERVICE_ROLE_KEY,
            'Content-Type': content_type,
            'Cache-Control': '3600',
            'x-upsert': 'true',
        },
    )

    try:
        with request.urlopen(req, timeout=30):
            pass
    except error.HTTPError as exc:
        detail = exc.read().decode('utf-8', errors='ignore')
        raise RuntimeError(f'Gagal upload ke Supabase Storage: {detail or exc.reason}') from exc
    except error.URLError as exc:
        raise RuntimeError(f'Gagal menghubungi Supabase Storage: {exc.reason}') from exc
    except Exception as exc:
        raise RuntimeError(f'Gagal upload ke Supabase Storage: {exc}') from exc

    return f'{base_url}/storage/v1/object/public/{bucket}/{encoded_path}'
