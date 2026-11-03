from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str
    jwt_secret: str
    jwt_expire_minutes: int = 30
    admin_secret: str
    cors_origins: str = "*"

    @property
    def origens(self) -> list[str]:
        """Origens liberadas no CORS, separadas por virgula."""
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


settings = Settings()