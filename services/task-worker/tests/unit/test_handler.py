import json
from uuid import uuid4

from task_worker.bootstrap.handler import handle


def record(message_id: str, body: str) -> dict[str, str]:
    return {"messageId": message_id, "body": body}


def test_valid_messages_are_not_reported() -> None:
    event = {"Records": [record("m1", json.dumps({"taskId": str(uuid4())}))]}
    assert handle(event) == {"batchItemFailures": []}


def test_invalid_messages_are_reported_individually() -> None:
    event = {
        "Records": [
            record("ok", json.dumps({"taskId": str(uuid4())})),
            record("not-json", "{"),
            record("not-uuid", json.dumps({"taskId": "nope"})),
            record("extra-field", json.dumps({"taskId": str(uuid4()), "x": 1})),
        ]
    }
    failures = [f["itemIdentifier"] for f in handle(event)["batchItemFailures"]]
    assert failures == ["not-json", "not-uuid", "extra-field"]
