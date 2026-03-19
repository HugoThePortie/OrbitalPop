extends Node

# ============================================================================
# IAP Manager for Orbital Pop (StoreKit 2)
# Single product: Remove Ads
# ============================================================================

signal purchase_completed(product_id: String)
signal purchase_failed(error: String)
signal restore_completed(success: bool)

const REMOVE_ADS_PRODUCT_ID = "com.werkzenog.orbitalpop.remove_ads"

var _iap_singleton = null
var _products: Dictionary = {}
var _ads_disabled: bool = false
var _is_purchasing: bool = false

func _ready() -> void:
	print("=== IAP Manager Starting ===")
	_load_ads_disabled_state()

	if Engine.has_singleton("IOSInAppPurchase"):
		_iap_singleton = Engine.get_singleton("IOSInAppPurchase")
		_iap_singleton.response.connect(_on_iap_response)
		_iap_singleton.request("startUpdateTask", {})
		_check_entitlements()
		_load_products()
		print("=== IAP Manager Ready ===")
	else:
		print("IOSInAppPurchase singleton not found - IAP disabled")

func _check_entitlements() -> void:
	if _iap_singleton:
		_iap_singleton.request("transactionCurrentEntitlements", {})

func _load_products() -> void:
	if _iap_singleton:
		_iap_singleton.request("products", {
			"productIDs": [REMOVE_ADS_PRODUCT_ID]
		})

func purchase_remove_ads() -> void:
	if _is_purchasing:
		return
	if _iap_singleton:
		_is_purchasing = true
		_iap_singleton.request("purchase", {
			"productID": REMOVE_ADS_PRODUCT_ID
		})
	else:
		purchase_failed.emit("IAP not available")

func restore_purchases() -> void:
	if _iap_singleton:
		_iap_singleton.request("appStoreSync", {})
	else:
		restore_completed.emit(false)

func is_ads_disabled() -> bool:
	return _ads_disabled

func get_remove_ads_price() -> String:
	if _products.has(REMOVE_ADS_PRODUCT_ID):
		return _products[REMOVE_ADS_PRODUCT_ID].get("displayPrice", "$2.99")
	return "$2.99"

func _on_iap_response(response_name: String, data: Dictionary) -> void:
	print("IAP Response: %s = %s" % [response_name, data])

	match response_name:
		"products":
			if data.get("result") == "success":
				for product in data.get("products", []):
					_products[product["id"]] = product

		"purchase":
			_is_purchasing = false
			if data.get("result") == "success":
				var product_id = data.get("productID", "")
				if product_id == REMOVE_ADS_PRODUCT_ID:
					_set_ads_disabled(true)
				purchase_completed.emit(product_id)
			else:
				purchase_failed.emit(data.get("error", "Purchase failed"))

		"transactionCurrentEntitlements":
			if data.get("result") == "success":
				for transaction in data.get("transactions", []):
					if transaction.get("productID") == REMOVE_ADS_PRODUCT_ID:
						if transaction.get("revocationDate", "") == "":
							if not _ads_disabled:
								_set_ads_disabled(true)

		"appStoreSync":
			_check_entitlements()
			restore_completed.emit(data.get("result") == "success")

		"startUpdateTask":
			if data.get("result") == "success" and data.has("productID"):
				if data.get("productID", "") == REMOVE_ADS_PRODUCT_ID:
					_set_ads_disabled(true)
					purchase_completed.emit(REMOVE_ADS_PRODUCT_ID)

func _set_ads_disabled(value: bool) -> void:
	if _ads_disabled != value:
		_ads_disabled = value
		_save_ads_disabled_state()

func _save_ads_disabled_state() -> void:
	var config = ConfigFile.new()
	config.load("user://save.cfg")
	config.set_value("iap", "ads_disabled", _ads_disabled)
	config.save("user://save.cfg")

func _load_ads_disabled_state() -> void:
	var config = ConfigFile.new()
	if config.load("user://save.cfg") == OK:
		_ads_disabled = config.get_value("iap", "ads_disabled", false)
