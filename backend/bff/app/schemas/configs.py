from pydantic import BaseModel


class ConfigItem(BaseModel):
    protocol: str
    label: str
    value: str


class ConfigListResponse(BaseModel):
    items: list[ConfigItem]
