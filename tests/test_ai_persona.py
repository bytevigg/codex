from youtube_buddy.ai import AIClient
from youtube_buddy.config import Settings


def test_enforce_persona_contract_prefixes_third_person(monkeypatch):
    client = AIClient.__new__(AIClient)
    client.settings = Settings()

    out = client.enforce_persona_contract("I can help with that", "Bluey")
    assert out.startswith("Bluey says")
    assert " I " not in f" {out} "
