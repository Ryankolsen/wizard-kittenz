extends Node

const _ENV_FILE := "res://nakama.env"

var _client: NakamaClient
var session: NakamaSession

signal authenticated(session: NakamaSession)

func _ready() -> void:
	var host := _env("NAKAMA_HOST", "127.0.0.1")
	var port := int(_env("NAKAMA_PORT", "7350"))
	var server_key := _env("NAKAMA_SERVER_KEY", "localdev_server_key")
	var scheme := _env("NAKAMA_SCHEME", "http")
	_client = Nakama.create_client(server_key, host, port, scheme)

const _SAVE_COLLECTION := "saves"
const _SAVE_KEY := "kitten"

func fetch_save_async(p_session: NakamaSession) -> Dictionary:
	var result = await _client.read_storage_objects_async(
		p_session,
		[NakamaStorageObjectId.new(_SAVE_COLLECTION, _SAVE_KEY, p_session.user_id)]
	)
	if result.is_exception() or result.objects.is_empty():
		return {}
	var parsed = JSON.parse_string(result.objects[0].value)
	if parsed is Dictionary:
		return parsed
	return {}

func upload_save_async(p_session: NakamaSession, dict: Dictionary) -> Error:
	var result = await _client.write_storage_objects_async(
		p_session,
		[NakamaWriteStorageObject.new(_SAVE_COLLECTION, _SAVE_KEY, 1, 1, JSON.stringify(dict), "")]
	)
	if result.is_exception():
		push_error("NakamaClient upload_save failed: " + result.get_exception().message)
		return FAILED
	return OK

func create_socket_async(p_session: NakamaSession) -> NakamaSocket:
	var socket: NakamaSocket = Nakama.create_socket_from(_client)
	var result = await socket.connect_async(p_session)
	if result.is_exception():
		push_error("NakamaClient socket connect failed: " + result.get_exception().message)
		return null
	return socket

func find_match_async(p_session: NakamaSession, room_code: String) -> String:
	var result = await _client.list_matches_async(p_session, 1, 4, 10, false, room_code, "")
	if result.is_exception() or result.matches.is_empty():
		return ""
	return result.matches[0].match_id

func authenticate_device_async(device_id: String) -> NakamaSession:
	var result: NakamaSession = await _client.authenticate_device_async(device_id)
	if result.is_exception():
		push_error("NakamaClient auth failed: " + result.get_exception().message)
		return null
	session = result
	authenticated.emit(session)
	return session

func _env(key: String, fallback: String) -> String:
	var os_val := OS.get_environment(key)
	if os_val != "":
		return os_val
	return _parse_env_file().get(key, fallback)

var _env_cache: Dictionary = {}
var _env_cache_loaded: bool = false

func _parse_env_file() -> Dictionary:
	if _env_cache_loaded:
		return _env_cache
	_env_cache_loaded = true
	if not FileAccess.file_exists(_ENV_FILE):
		return _env_cache
	var file := FileAccess.open(_ENV_FILE, FileAccess.READ)
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var eq := line.find("=")
		if eq > 0:
			_env_cache[line.left(eq).strip_edges()] = line.substr(eq + 1).strip_edges()
	return _env_cache
