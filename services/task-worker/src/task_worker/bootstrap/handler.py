"""SQS entry point. Returns partial batch failures so only failed messages are retried.

The handler is empty for now: it validates each message against the TaskMessage contract and
reports the ones that do not parse. Delivery is wired in once the DeliverTask use case exists.
"""

import json
import logging
from typing import Any, TypedDict

from pydantic import ValidationError

from task_worker.contracts.task_message import TaskMessage

logger = logging.getLogger("task_worker")
logger.setLevel(logging.INFO)


class BatchItemFailure(TypedDict):
    itemIdentifier: str


class BatchResponse(TypedDict):
    batchItemFailures: list[BatchItemFailure]


def handle(event: dict[str, Any], _context: object = None) -> BatchResponse:
    failures: list[BatchItemFailure] = []
    for record in event.get("Records", []):
        message_id = str(record.get("messageId", ""))
        try:
            message = TaskMessage.model_validate(json.loads(record.get("body", "")))
        except (json.JSONDecodeError, ValidationError):
            logger.warning("invalid task message", extra={"message_id": message_id})
            failures.append({"itemIdentifier": message_id})
            continue
        logger.info("task received", extra={"task_id": str(message.taskId)})
    return {"batchItemFailures": failures}
