class_name NakamaClient
extends Node
## Client HTTP minimal pour Nakama : authentification par appareil et appels RPC.
## Pas de dépendance externe : HTTPRequest de Godot, utilisable sur Android, Windows et Linux.
## Chaque méthode renvoie un Dictionary ; en cas d'échec : {"ok": false, "error": "..."}.

const TIMEOUT_SECONDS := 10.0

var base_url := ""
var server_key := "defaultkey"
var token := ""


func _init(p_base_url: String, p_server_key := "defaultkey") -> void:
	base_url = p_base_url.trim_suffix("/")
	server_key = p_server_key


func is_authenticated() -> bool:
	return token != ""


## Crée le compte au premier lancement, puis reconnecte le même appareil.
func authenticate_device(device_id: String) -> Dictionary:
	var auth := Marshalls.utf8_to_base64(server_key + ":")
	var res := await _request("/v2/account/authenticate/device?create=true",
		["Authorization: Basic " + auth], JSON.stringify({"id": device_id}))
	if not res.ok:
		return res
	token = String(res.data.get("token", ""))
	return {"ok": token != "", "error": "" if token != "" else "jeton_absent"}


## Appelle une RPC du module serveur ; renvoie la réponse JSON du module.
func call_rpc(rpc_name: String, payload: Dictionary = {}) -> Dictionary:
	if token == "":
		return {"ok": false, "error": "non_connecte"}
	# L'API HTTP de Nakama attend la charge utile sous forme de chaîne JSON.
	var res := await _request("/v2/rpc/" + rpc_name.uri_encode(),
		["Authorization: Bearer " + token], JSON.stringify(JSON.stringify(payload)))
	if not res.ok:
		return res
	var inner: Variant = JSON.parse_string(String(res.data.get("payload", "")))
	if typeof(inner) != TYPE_DICTIONARY:
		return {"ok": false, "error": "reponse_invalide"}
	return inner


func _request(path: String, headers: Array, body: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SECONDS
	add_child(http)
	var all_headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	all_headers.append_array(PackedStringArray(headers))
	var err := http.request(base_url + path, all_headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "reseau"}
	var result: Array = await http.request_completed
	http.queue_free()
	var status: int = result[0]
	var code: int = result[1]
	var text: String = (result[3] as PackedByteArray).get_string_from_utf8()
	if status != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "reseau"}
	var data: Variant = JSON.parse_string(text) if text != "" else {}
	if typeof(data) != TYPE_DICTIONARY:
		data = {}
	if code < 200 or code >= 300:
		# Erreur levée par le module (ex. requete_invalide) ou refus d'authentification.
		return {"ok": false, "error": String(data.get("message", "http_%d" % code)), "code": code}
	return {"ok": true, "data": data}
