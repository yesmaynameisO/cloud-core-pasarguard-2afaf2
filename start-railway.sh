#!/usr/bin/env bash
set -e

export PATH="/code/.venv/bin:$PATH"
export UVICORN_HOST="0.0.0.0"
export UVICORN_PORT="${PORT:-8000}"
export SQLALCHEMY_DATABASE_URL="${SQLALCHEMY_DATABASE_URL:-sqlite+aiosqlite:///db.sqlite3}"
export ROLE="${ROLE:-all-in-one}"
export UVICORN_PROXY_HEADERS="true"
export UVICORN_FORWARDED_ALLOW_IPS="*"

echo "Starting PasarGuard panel on port ${UVICORN_PORT}..."

# ۱. پچ main.py برای آدرس 0.0.0.0
sed -i 's/bind_args\["host"\] = ip/bind_args["host"] = server_settings.host/' /code/main.py || true

# ۲. مایگریشن دیتابیس
python -m alembic upgrade head || true

# ۳. اعطای دسترسی کامل و همگام‌سازی فیلدها
if [ -n "${SUDO_USERNAME:-}" ] && [ -n "${SUDO_PASSWORD:-}" ]; then
    echo "Ensuring sudo admin '${SUDO_USERNAME}' exists with full permissions..."
    python -c "
import asyncio
import os
import inspect
import pkgutil
import importlib
from sqlalchemy import text

async def main():
    username = os.environ.get('SUDO_USERNAME', 'admin')
    password = os.environ.get('SUDO_PASSWORD', 'admin')
    
    try:
        from app.db.base import GetDB
    except ImportError:
        from app.db import GetDB

    from app.db.models import Admin

    get_password_hash = None
    import app
    for importer, modname, ispkg in pkgutil.walk_packages(app.__path__, app.__name__ + '.'):
        try:
            mod = importlib.import_module(modname)
            for attr in ['hash_password', 'get_password_hash', 'get_password_hash_func']:
                if hasattr(mod, attr) and callable(getattr(mod, attr)):
                    get_password_hash = getattr(mod, attr)
                    break
            if get_password_hash:
                break
        except Exception:
            pass

    if not get_password_hash:
        try:
            from pwdlib import PasswordHash
            pwd_context = PasswordHash.recommended()
            get_password_hash = pwd_context.hash
        except Exception:
            import hashlib
            get_password_hash = lambda p: hashlib.sha256(p.encode()).hexdigest()

    if inspect.iscoroutinefunction(get_password_hash):
        hashed = await get_password_hash(password)
    else:
        hashed = get_password_hash(password)

    async with GetDB() as db:
        try:
            from app.db.crud.admin import get_admin
            admin = await get_admin(db, username=username)
            if admin:
                admin.hashed_password = hashed
                db.add(admin)
                await db.commit()
            else:
                admin = Admin(username=username, hashed_password=hashed)
                db.add(admin)
                await db.commit()

            # تنظیم فیلدها با فرمت استاندارد نیتیو
            await db.execute(
                text('UPDATE admins SET role_id = 1, permission_overrides = NULL WHERE username = :u'),
                {'u': username}
            )
            await db.commit()
            print(f'Admin {username} successfully initialized!')
        except Exception as e:
            print('Admin initialization error:', e)

asyncio.run(main())
" || true
fi

# ۴. اجرای سرویس
exec /code/start.sh
