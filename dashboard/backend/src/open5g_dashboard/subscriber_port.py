"""Subscriber store port.

The lab Compose project has no Open5GS WebUI, so the only write path is the
MongoDB ``subscribers`` collection. An empty URI disables the port. The port
never returns Ki, OPc, or the MongoDB URI.
"""

from __future__ import annotations

from typing import Any, Protocol
from urllib.parse import parse_qs, urlsplit

from open5g_dashboard.domain import ProfileError
from open5g_dashboard.open5gs_schema import drop_secrets, plan_session_update, project_subscriber

_SAFE_ERRORS = {
    "TimeoutError": "MongoDB timed out",
    "ServerSelectionTimeoutError": "MongoDB timed out",
    "ConnectionFailure": "MongoDB connection failed",
    "NetworkTimeout": "MongoDB timed out",
    "AutoReconnect": "MongoDB connection failed",
    "ConfigurationError": "MongoDB URI was rejected",
}
_PUBLIC_PROJECTION = {"security": 0}


class SubscriberUnavailable(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


class SubscriberConflict(Exception):
    def __init__(self) -> None:
        super().__init__("Subscriber document changed before the write was applied")
        self.code = "subscriber_conflict"
        self.message = "Subscriber document changed before the write was applied"


def describe_mongo_target(uri: str) -> dict[str, str | bool]:
    """Say whether auth and TLS are requested. The host is not included."""
    if not uri:
        return {"configured": False, "auth": "not_configured", "tls": "not_configured"}
    parsed = urlsplit(uri)
    flags = [item.lower() for item in parse_qs(parsed.query).get("tls", []) + parse_qs(parsed.query).get("ssl", [])]
    tls = "enabled" if any(flag in {"1", "true", "yes"} for flag in flags) else "not_requested"
    return {"configured": True, "auth": "present" if parsed.username else "absent", "tls": tls}


def _safe_message(exc: Exception) -> str:
    return _SAFE_ERRORS.get(type(exc).__name__, "MongoDB request failed")


class SubscriberPort(Protocol):
    configured: bool

    def describe(self) -> dict[str, str | bool]: ...

    def probe(self) -> dict[str, Any]: ...

    def read(self, imsi: str) -> dict[str, Any]: ...

    def provision(self, imsi: str, content: dict[str, Any]) -> dict[str, Any]: ...


class DisabledSubscriberPort:
    configured = False

    def describe(self) -> dict[str, str | bool]:
        return describe_mongo_target("")

    def probe(self) -> dict[str, Any]:
        return {"name": "mongo-subscriber", "status": "not_configured", "error": None, "http_status": None}

    def read(self, imsi: str) -> dict[str, Any]:
        return {
            "status": "not_configured",
            "found": False,
            "configured": False,
            "imsi": imsi,
            "credentials_present": False,
            "attach_ready": False,
            "security_returned": False,
            "sessions": [],
            "session_count": 0,
            "live_gx_rar": False,
        }

    def provision(self, imsi: str, content: dict[str, Any], *, role: str = "student", apn_allowlist: tuple[str, ...] = ()) -> dict[str, Any]:
        raise SubscriberUnavailable("subscriber_store_not_configured", "OPEN5G_MONGO_URI is empty")


class MongoSubscriberPort:
    configured = True

    def __init__(self, uri: str, database: str, collection: str, timeout_ms: int, client: Any = None):
        self._uri = uri
        self._database = database
        self._collection = collection
        self._timeout_ms = timeout_ms
        self._client = client

    def describe(self) -> dict[str, str | bool]:
        return describe_mongo_target(self._uri)

    def _client_handle(self):
        if self._client is not None:
            return self._client
        from pymongo import MongoClient

        self._client = MongoClient(
            self._uri,
            serverSelectionTimeoutMS=self._timeout_ms,
            connectTimeoutMS=self._timeout_ms,
            socketTimeoutMS=self._timeout_ms,
        )
        return self._client

    def _coll(self):
        return self._client_handle()[self._database][self._collection]

    def _unique_imsi_index(self, collection) -> bool | None:
        """Read-only. Never creates or alters an index."""
        try:
            indexes = collection.list_indexes()
        except Exception:
            return None
        for info in indexes:
            key = info.get("key") or {}
            if list(key.keys()) == ["imsi"] and bool(info.get("unique")):
                return True
        return False

    def probe(self) -> dict[str, Any]:
        try:
            collection = self._coll()
            collection.find_one({"imsi": "__open5g_ping__"}, {"_id": 1})
            unique = self._unique_imsi_index(collection)
        except Exception as exc:
            return {
                "name": "mongo-subscriber",
                "status": "down",
                "error": _safe_message(exc),
                "http_status": None,
                "imsi_unique_index": None,
                "warning": None,
            }
        warning = None if unique else "no_unique_imsi_index"
        return {
            "name": "mongo-subscriber",
            "status": "reachable",
            "error": None,
            "http_status": None,
            "imsi_unique_index": unique,
            "warning": warning,
        }

    def _has_credentials(self, imsi: str) -> bool:
        try:
            found = self._coll().count_documents(
                {
                    "imsi": imsi,
                    "security.k": {"$exists": True, "$nin": [None, ""]},
                    "security.opc": {"$exists": True, "$nin": [None, ""]},
                }
            )
        except Exception:
            return False
        return found == 1

    def read(self, imsi: str) -> dict[str, Any]:
        try:
            document = self._coll().find_one({"imsi": imsi}, _PUBLIC_PROJECTION)
        except Exception as exc:
            raise SubscriberUnavailable("subscriber_store_unavailable", _safe_message(exc)) from None
        if document is None:
            return {
                "status": "absent",
                "found": False,
                "configured": True,
                "imsi": imsi,
                "credentials_present": False,
                "attach_ready": False,
                "security_returned": False,
                "sessions": [],
                "session_count": 0,
                "live_gx_rar": False,
            }
        projected = project_subscriber(document, imsi)
        present = self._has_credentials(imsi)
        projected["credentials_present"] = present
        projected["attach_ready"] = present
        return projected

    def provision(
        self,
        imsi: str,
        content: dict[str, Any],
        *,
        role: str = "student",
        apn_allowlist: tuple[str, ...] = (),
    ) -> dict[str, Any]:
        try:
            collection = self._coll()
            existing = collection.find_one({"imsi": imsi}, _PUBLIC_PROJECTION)
            patch = plan_session_update(existing, content, role=role, apn_allowlist=apn_allowlist)
            query: dict[str, Any] = {
                "imsi": imsi,
                f"slice.{patch.slice_index}.session": {"$size": patch.expected_session_count},
            }
            if patch.expected_generation is None:
                query["open5g_dashboard.generation"] = {"$exists": False}
            else:
                query["open5g_dashboard.generation"] = patch.expected_generation
            generation = 1 if patch.expected_generation is None else patch.expected_generation + 1
            if patch.session_index is None:
                if patch.new_session is None:
                    raise ProfileError("session_not_selected", "No subscriber session could be selected")
                query[f"slice.{patch.slice_index}.session.name"] = {"$ne": patch.session_name}
                result = collection.update_one(
                    query,
                    {
                        "$push": {f"slice.{patch.slice_index}.session": patch.new_session},
                        "$set": {"open5g_dashboard.generation": generation},
                    },
                )
            else:
                prefix = f"slice.{patch.slice_index}.session.{patch.session_index}"
                query[f"{prefix}.name"] = patch.session_name
                result = collection.update_one(
                    query,
                    {
                        "$set": {
                            f"{prefix}.qos": patch.qos,
                            f"{prefix}.ambr": patch.ambr,
                            f"{prefix}.pcc_rule": patch.pcc_rule,
                            "open5g_dashboard.generation": generation,
                        }
                    },
                )
            if getattr(result, "matched_count", 0) != 1:
                raise SubscriberConflict()
            stored = collection.find_one({"imsi": imsi}, _PUBLIC_PROJECTION)
        except (SubscriberUnavailable, ProfileError, SubscriberConflict):
            raise
        except Exception as exc:
            raise SubscriberUnavailable("subscriber_store_unavailable", _safe_message(exc)) from None
        if stored is None:
            raise SubscriberUnavailable("subscriber_store_unavailable", "MongoDB read after write failed")
        body = project_subscriber(stored, imsi)
        present = self._has_credentials(imsi)
        body["credentials_present"] = present
        body["attach_ready"] = present
        previous = None
        if existing is not None and patch.session_index is not None:
            sessions = existing["slice"][patch.slice_index].get("session") or []
            current = sessions[patch.session_index] if patch.session_index < len(sessions) else {}
            previous = {
                "slice_index": patch.slice_index,
                "session_index": patch.session_index,
                "name": patch.session_name,
                "qos": current.get("qos"),
                "ambr": current.get("ambr"),
                "pcc_rule": current.get("pcc_rule") or [],
                "generation": generation,
            }
        return drop_secrets(
            {
                "status": "written",
                "created": False,
                "session_created": patch.session_index is None,
                "generation": generation,
                "effect": "subscriber_document_only",
                "session_effect": "not_pushed_to_active_session",
                "live_gx_rar": False,
                "notes": patch.notes,
                "previous_session": previous,
                "subscriber": body,
            }
        )

    def restore_session(self, imsi: str, previous: dict[str, Any]) -> None:
        """Put back the session fields captured before a write. Does not touch security."""
        try:
            prefix = f"slice.{previous['slice_index']}.session.{previous['session_index']}"
            generation = int(previous["generation"])
            result = self._coll().update_one(
                {
                    "imsi": imsi,
                    f"{prefix}.name": previous["name"],
                    "open5g_dashboard.generation": generation,
                },
                {
                    "$set": {
                        f"{prefix}.qos": previous.get("qos"),
                        f"{prefix}.ambr": previous.get("ambr"),
                        f"{prefix}.pcc_rule": previous.get("pcc_rule") or [],
                        "open5g_dashboard.generation": generation + 1,
                    }
                },
            )
        except Exception as exc:
            raise SubscriberUnavailable("subscriber_store_unavailable", _safe_message(exc)) from None
        if getattr(result, "matched_count", 0) != 1:
            raise SubscriberConflict()


def build_subscriber_port(settings) -> DisabledSubscriberPort | MongoSubscriberPort:
    if not settings.mongo_uri:
        return DisabledSubscriberPort()
    return MongoSubscriberPort(
        settings.mongo_uri,
        settings.mongo_database,
        settings.mongo_collection,
        settings.mongo_timeout_ms,
    )
