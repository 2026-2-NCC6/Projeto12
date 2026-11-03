from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict

_backend_dir = Path(__file__).resolve().parent.parent.parent
_env_path = _backend_dir / ".env"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=str(_env_path) if _env_path.exists() else ".env",
        extra="ignore",
    )

    database_url: str = "sqlite:///tobias.db"
    jwt_secret: str = "default_secret_key_tobias_2026_dev_mode_token"
    jwt_expire_minutes: int = 30
    admin_secret: str = "default_admin_secret_tobias_2026_dev_mode_key"


settings = Settings()
