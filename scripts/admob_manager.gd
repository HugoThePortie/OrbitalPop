extends Node

# ============================================================================
# AdMob Manager for Orbital Pop
# Uses godot-sdk-integrations/godot-admob v5.3
# ============================================================================

signal ad_loaded
signal ad_failed
signal ad_rewarded
signal ad_closed

var _admob: Admob = null
var _ad_loaded: bool = false

# Production ad unit (switch to this for App Store release)
#const REWARDED_AD_ID = "ca-app-pub-4474484017776291/4121201348"
# Google's test ad unit - use for development
const REWARDED_AD_ID = "ca-app-pub-3940256099942544/1712485313"

func _ready() -> void:
	print("=== AdMob Manager Starting (v5.3) ===")
	print("[AdMob] Engine.has_singleton('AdmobPlugin') = %s" % Engine.has_singleton("AdmobPlugin"))

	# Create and configure the Admob node
	_admob = Admob.new()
	_admob.name = "Admob"

	# Configure for development (set is_real = true for production)
	_admob.is_real = false
	_admob.ios_debug_rewarded_id = REWARDED_AD_ID
	_admob.ios_real_rewarded_id = REWARDED_AD_ID
	_admob.test_device_hashed_ids = ["7391697a1edcfe6c6eefd6363ab5797f"]

	# Enable ATT for iOS 14.5+ compliance
	_admob.att_enabled = true
	_admob.att_text = "Your data helps us show relevant ads and improve your experience."

	# Add to scene tree (triggers Admob._ready())
	add_child(_admob)
	print("[AdMob] Admob node added to tree, _plugin_singleton found = %s" % (_admob._plugin_singleton != null))

	# Connect signals
	_connect_signals()

	# Initialize
	_admob.initialize()

	print("=== AdMob Manager Ready ===")

func _connect_signals() -> void:
	_admob.initialization_completed.connect(_on_init_complete)
	_admob.rewarded_ad_loaded.connect(_on_rewarded_ad_loaded)
	_admob.rewarded_ad_failed_to_load.connect(_on_rewarded_ad_failed)
	_admob.rewarded_ad_failed_to_show_full_screen_content.connect(_on_rewarded_ad_failed_to_show)
	_admob.rewarded_ad_dismissed_full_screen_content.connect(_on_rewarded_ad_closed)
	_admob.rewarded_ad_user_earned_reward.connect(_on_user_earned_reward)

func _on_init_complete(status: InitializationStatus) -> void:
	print(">>> AdMob initialized!")
	_load_rewarded_ad()

func _load_rewarded_ad() -> void:
	if _admob:
		print("Loading rewarded ad: %s" % REWARDED_AD_ID)
		_admob.load_rewarded_ad()

func _on_rewarded_ad_loaded(ad_info: AdInfo, response_info: ResponseInfo) -> void:
	print(">>> Rewarded ad LOADED!")
	_ad_loaded = true
	ad_loaded.emit()

func _on_rewarded_ad_failed(ad_info: AdInfo, error_data: LoadAdError) -> void:
	print(">>> Rewarded ad FAILED to load: %s" % error_data.get_message())
	_ad_loaded = false
	ad_failed.emit()
	await get_tree().create_timer(5.0).timeout
	_load_rewarded_ad()

func _on_rewarded_ad_failed_to_show(ad_info: AdInfo, error_data: AdError) -> void:
	print(">>> Rewarded ad FAILED to show: %s" % error_data.get_message())
	_ad_loaded = false
	ad_failed.emit()
	_load_rewarded_ad()

func _on_user_earned_reward(ad_info: AdInfo, reward_data: RewardItem) -> void:
	print(">>> REWARD EARNED! type=%s amount=%d" % [reward_data.get_type(), reward_data.get_amount()])
	ad_rewarded.emit()

func _on_rewarded_ad_closed(ad_info: AdInfo) -> void:
	print(">>> Rewarded ad closed")
	_ad_loaded = false
	ad_closed.emit()
	_load_rewarded_ad()

func show_rewarded_ad() -> void:
	var actually_loaded = _admob.is_rewarded_ad_loaded() if _admob else false
	print("show_rewarded_ad() called, plugin_loaded=%s" % actually_loaded)
	if _admob and actually_loaded:
		print("Showing rewarded ad...")
		_admob.show_rewarded_ad()
	else:
		print("Ad not ready")
		_ad_loaded = false
		ad_failed.emit()
		_load_rewarded_ad()

func load_rewarded_ad() -> void:
	_load_rewarded_ad()

func is_ad_ready() -> bool:
	return _admob.is_rewarded_ad_loaded() if _admob else false
