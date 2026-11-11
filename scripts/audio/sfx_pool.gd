extends Node

## Non-positional round-robin pool of AudioStreamPlayers used by sfx.gd. Plays requested before the
## pool enters the tree are queued and flushed on _ready.

const EXIT_FLUSH_MIN_MS: int = 150

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _pending: Array[Array] = []
var _was_playing: bool = false


func setup(size: int, bus: StringName) -> void:
	name = "SfxPool"
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i: int in size:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		# Children leave the tree before the parent's _exit_tree, and a player leaving the tree only
		# pauses its playback, which then stays in the AudioServer list forever and leaks at exit.
		p.tree_exiting.connect(_release_player.bind(p))
		add_child(p)
		_players.append(p)


func _ready() -> void:
	for item: Array in _pending:
		play_stream(item[0], item[1], item[2])
	_pending.clear()


func _exit_tree() -> void:
	# The mixer thread finishes the fade-out of stopped playbacks asynchronously; give it a few
	# mix buffers so the playback nodes are released before the AudioServer shuts down. The dummy
	# (headless) driver reports zero latency but mixes in coarse steps, hence the floor.
	if _was_playing:
		OS.delay_msec(maxi(EXIT_FLUSH_MIN_MS, int(AudioServer.get_output_latency() * 3000.0) + 40))


func play_stream(stream: AudioStream, volume_db: float, pitch: float) -> void:
	if not is_inside_tree():
		_pending.append([stream, volume_db, pitch])
		return
	var p: AudioStreamPlayer = _pick_player()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = clampf(pitch, 0.05, 8.0)
	p.play()


func _pick_player() -> AudioStreamPlayer:
	var count: int = _players.size()
	for k: int in count:
		var p: AudioStreamPlayer = _players[(_next + k) % count]
		if not p.playing:
			_next = (_next + k + 1) % count
			return p
	var oldest: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % count
	return oldest


## Called by loop handles (children of the pool) when their player leaves the tree while playing.
func note_playing() -> void:
	_was_playing = true


func _release_player(p: AudioStreamPlayer) -> void:
	if p.playing:
		_was_playing = true
	p.stop()
	p.stream = null
