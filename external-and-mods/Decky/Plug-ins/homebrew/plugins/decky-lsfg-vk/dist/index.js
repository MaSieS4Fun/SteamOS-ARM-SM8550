// Decky Loader will pass this api in, it's versioned to allow for backwards compatibility.
// @ts-ignore

// Prevents it from being duplicated in output.
const manifest = {"name":"Decky LSFG-VK","author":"Kurt Himebauch (xXJSONDeruloXx)","flags":[],"api_version":1,"publish":{"tags":["installer","vulkan","lsfg","framegen","lossless","scaling"],"description":"Enable lossless scaling frame generation on the Steam Deck using lsfg-vk compatibility layer.","image":"https://raw.githubusercontent.com/xXJSONDeruloXx/decky-lsfg-vk/refs/heads/main/assets/Decky_LSFG-VK_Master_1.png"}};
const API_VERSION = 2;
const internalAPIConnection = window.__DECKY_SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED_deckyLoaderAPIInit;
// Initialize
if (!internalAPIConnection) {
    throw new Error('[@decky/api]: Failed to connect to the loader as as the loader API was not initialized. This is likely a bug in Decky Loader.');
}
// Version 1 throws on version mismatch so we have to account for that here.
let api;
try {
    api = internalAPIConnection.connect(API_VERSION, manifest.name);
}
catch {
    api = internalAPIConnection.connect(1, manifest.name);
    console.warn(`[@decky/api] Requested API version ${API_VERSION} but the running loader only supports version 1. Some features may not work.`);
}
if (api._version != API_VERSION) {
    console.warn(`[@decky/api] Requested API version ${API_VERSION} but the running loader only supports version ${api._version}. Some features may not work.`);
}
const callable = api.callable;
const toaster = api.toaster;
const definePlugin = (fn) => {
    return (...args) => {
        // TODO: Maybe wrap this
        return fn(...args);
    };
};

var DefaultContext = {
  color: undefined,
  size: undefined,
  className: undefined,
  style: undefined,
  attr: undefined
};
var IconContext = SP_REACT.createContext && /*#__PURE__*/SP_REACT.createContext(DefaultContext);

var _excluded = ["attr", "size", "title"];
function _objectWithoutProperties(source, excluded) { if (source == null) return {}; var target = _objectWithoutPropertiesLoose(source, excluded); var key, i; if (Object.getOwnPropertySymbols) { var sourceSymbolKeys = Object.getOwnPropertySymbols(source); for (i = 0; i < sourceSymbolKeys.length; i++) { key = sourceSymbolKeys[i]; if (excluded.indexOf(key) >= 0) continue; if (!Object.prototype.propertyIsEnumerable.call(source, key)) continue; target[key] = source[key]; } } return target; }
function _objectWithoutPropertiesLoose(source, excluded) { if (source == null) return {}; var target = {}; for (var key in source) { if (Object.prototype.hasOwnProperty.call(source, key)) { if (excluded.indexOf(key) >= 0) continue; target[key] = source[key]; } } return target; }
function _extends() { _extends = Object.assign ? Object.assign.bind() : function (target) { for (var i = 1; i < arguments.length; i++) { var source = arguments[i]; for (var key in source) { if (Object.prototype.hasOwnProperty.call(source, key)) { target[key] = source[key]; } } } return target; }; return _extends.apply(this, arguments); }
function ownKeys(e, r) { var t = Object.keys(e); if (Object.getOwnPropertySymbols) { var o = Object.getOwnPropertySymbols(e); r && (o = o.filter(function (r) { return Object.getOwnPropertyDescriptor(e, r).enumerable; })), t.push.apply(t, o); } return t; }
function _objectSpread(e) { for (var r = 1; r < arguments.length; r++) { var t = null != arguments[r] ? arguments[r] : {}; r % 2 ? ownKeys(Object(t), !0).forEach(function (r) { _defineProperty(e, r, t[r]); }) : Object.getOwnPropertyDescriptors ? Object.defineProperties(e, Object.getOwnPropertyDescriptors(t)) : ownKeys(Object(t)).forEach(function (r) { Object.defineProperty(e, r, Object.getOwnPropertyDescriptor(t, r)); }); } return e; }
function _defineProperty(obj, key, value) { key = _toPropertyKey(key); if (key in obj) { Object.defineProperty(obj, key, { value: value, enumerable: true, configurable: true, writable: true }); } else { obj[key] = value; } return obj; }
function _toPropertyKey(t) { var i = _toPrimitive(t, "string"); return "symbol" == typeof i ? i : i + ""; }
function _toPrimitive(t, r) { if ("object" != typeof t || !t) return t; var e = t[Symbol.toPrimitive]; if (void 0 !== e) { var i = e.call(t, r || "default"); if ("object" != typeof i) return i; throw new TypeError("@@toPrimitive must return a primitive value."); } return ("string" === r ? String : Number)(t); }
function Tree2Element(tree) {
  return tree && tree.map((node, i) => /*#__PURE__*/SP_REACT.createElement(node.tag, _objectSpread({
    key: i
  }, node.attr), Tree2Element(node.child)));
}
function GenIcon(data) {
  return props => /*#__PURE__*/SP_REACT.createElement(IconBase, _extends({
    attr: _objectSpread({}, data.attr)
  }, props), Tree2Element(data.child));
}
function IconBase(props) {
  var elem = conf => {
    var {
        attr,
        size,
        title
      } = props,
      svgProps = _objectWithoutProperties(props, _excluded);
    var computedSize = size || conf.size || "1em";
    var className;
    if (conf.className) className = conf.className;
    if (props.className) className = (className ? className + " " : "") + props.className;
    return /*#__PURE__*/SP_REACT.createElement("svg", _extends({
      stroke: "currentColor",
      fill: "currentColor",
      strokeWidth: "0"
    }, conf.attr, attr, svgProps, {
      className: className,
      style: _objectSpread(_objectSpread({
        color: props.color || conf.color
      }, conf.style), props.style),
      height: computedSize,
      width: computedSize,
      xmlns: "http://www.w3.org/2000/svg"
    }), title && /*#__PURE__*/SP_REACT.createElement("title", null, title), props.children);
  };
  return IconContext !== undefined ? /*#__PURE__*/SP_REACT.createElement(IconContext.Consumer, null, conf => elem(conf)) : elem(DefaultContext);
}

// THIS FILE IS AUTO GENERATED
function GiPlasticDuck (props) {
  return GenIcon({"tag":"svg","attr":{"viewBox":"0 0 512 512"},"child":[{"tag":"path","attr":{"d":"M322.8 50.96c-28.1.66-52.4 13.13-65.8 38.48-13.4 25.36-16.1 64.96 3.6 120.46v.2c3.2 9.4 2.4 19.2-2.6 26.4-5 7.3-12.9 11.6-21.9 14.5-18 5.8-42.3 6.4-69.3 4.5-48.7-3.5-105.4-15.7-142.38-27.9-2.34 56.3 13.28 113.7 45.28 157.2 34.2 46.5 86.2 77.5 156 76.2 45.3-.8 98.8-7.4 140.2-25.5 41.4-18 70-45.8 71.3-92.4v-.1c.6-19.8-18.4-47.1-36.3-74.7-8.9-13.8-17.3-27.8-21.9-42.4-4.6-14.5-5-30.3 3.2-44.5l.2-.3.2-.3c22.2-32.6 18.7-64.5 3.9-89.24-14.7-24.79-41.5-41.12-63.7-40.6zm30.5 42.05a18 18 0 0 1 18 17.99 18 18 0 0 1-18 18 18 18 0 0 1-18-18 18 18 0 0 1 18-17.99zM416 130.2c.4 14.3-2.4 29.3-9.2 44.2 19.5-1.2 38.8-3.4 53.6-8.4 9.6-3.1 17.1-7.4 21.8-12.3 2.7-2.9 4.5-6 5.6-9.7-24.7.3-51-6.3-71.8-13.8zm-72.6 142.5c6.5 13.6 6.1 28.2.7 40.9-5.4 12.7-15.3 23.8-27.7 33.9-24.7 20-59.6 35.5-93.6 44.8-34 9.3-66.4 12.8-88.7 4.8-11.2-4-20.6-12.6-22.2-24.5-1.6-12 3.6-24.8 14.4-39.8l14.6 10.6c-9.4 13-11.8 22.2-11.2 26.8.7 4.7 3.1 7.3 10.4 10 14.7 5.2 45.9 3.5 78-5.3 32-8.7 65.3-23.8 87-41.4 10.8-8.8 18.7-18.2 22.4-27 3.8-8.8 4.1-16.8-.3-26z"},"child":[]}]})(props);
}

// API functions
const installLsfgVk = callable("install_lsfg_vk");
const uninstallLsfgVk = callable("uninstall_lsfg_vk");
const checkLsfgVkInstalled = callable("check_lsfg_vk_installed");
const checkLosslessScalingDll = callable("check_lossless_scaling_dll");
const getDllStats = callable("get_dll_stats");
const getLsfgConfig = callable("get_lsfg_config");
callable("get_config_schema");
const getLaunchOption = callable("get_launch_option");
const getConfigFileContent = callable("get_config_file_content");
const getLaunchScriptContent = callable("get_launch_script_content");
const checkFgmodDirectory = callable("check_fgmod_directory");
// Flatpak management API functions
const checkFlatpakExtensionStatus = callable("check_flatpak_extension_status");
const installFlatpakExtension = callable("install_flatpak_extension");
const uninstallFlatpakExtension = callable("uninstall_flatpak_extension");
const getFlatpakApps = callable("get_flatpak_apps");
const setFlatpakAppOverride = callable("set_flatpak_app_override");
const removeFlatpakAppOverride = callable("remove_flatpak_app_override");
// Updated config function using object-based configuration (single source of truth)
const updateLsfgConfig = callable("update_lsfg_config");
// Legacy helper function for backward compatibility
const updateLsfgConfigFromObject = async (config) => {
    return updateLsfgConfig(config);
};
// Self-updater API functions
// Profile management API functions
const getProfiles = callable("get_profiles");
const createProfile = callable("create_profile");
const deleteProfile = callable("delete_profile");
const renameProfile = callable("rename_profile");
const setCurrentProfile = callable("set_current_profile");
const updateProfileConfig = callable("update_profile_config");

// src/config/generatedConfigSchema.ts
// Configuration field type enum - matches Python
var ConfigFieldType;
(function (ConfigFieldType) {
    ConfigFieldType["BOOLEAN"] = "boolean";
    ConfigFieldType["INTEGER"] = "integer";
    ConfigFieldType["FLOAT"] = "float";
    ConfigFieldType["STRING"] = "string";
})(ConfigFieldType || (ConfigFieldType = {}));
const MULTIPLIER = "multiplier";
const FLOW_SCALE = "flow_scale";
const PERFORMANCE_MODE = "performance_mode";
const HDR_MODE = "hdr_mode";
const EXPERIMENTAL_PRESENT_MODE = "experimental_present_mode";
const DXVK_FRAME_RATE = "dxvk_frame_rate";
const DISABLE_STEAMDECK_MODE = "disable_steamdeck_mode";
const MANGOHUD_WORKAROUND = "mangohud_workaround";
const DISABLE_VKBASALT = "disable_vkbasalt";
const FORCE_ENABLE_VKBASALT = "force_enable_vkbasalt";
const ENABLE_WSI = "enable_wsi";
const ENABLE_ZINK = "enable_zink";
function getDefaults() {
    return {
        dll: "/games/Lossless Scaling/Lossless.dll",
        no_fp16: false,
        multiplier: 1,
        flow_scale: 0.8,
        performance_mode: false,
        hdr_mode: false,
        experimental_present_mode: "fifo",
        dxvk_frame_rate: 0,
        enable_wow64: false,
        disable_steamdeck_mode: false,
        mangohud_workaround: false,
        disable_vkbasalt: false,
        force_enable_vkbasalt: false,
        enable_wsi: false,
        enable_zink: false,
    };
}

/**
 * Configuration schema and management for LSFG VK plugin
 *
 * This file re-exports auto-generated configuration constants from generatedConfigSchema.ts
 * and provides the ConfigurationManager class for handling configuration operations.
 */
/**
 * Configuration management class
 * Handles CRUD operations for plugin configuration
 */
class ConfigurationManager {
    constructor() {
        this._config = null;
        this.getConfiguration = callable("get_configuration");
        this.resetConfiguration = callable("reset_configuration");
    }
    static getInstance() {
        if (!ConfigurationManager.instance) {
            ConfigurationManager.instance = new ConfigurationManager();
        }
        return ConfigurationManager.instance;
    }
    /**
     * Get default configuration values
     */
    static getDefaults() {
        return getDefaults();
    }
    /**
     * Load configuration from backend
     */
    async loadConfig() {
        try {
            const result = await this.getConfiguration();
            if (result.success && result.data) {
                this._config = result.data;
                return this._config;
            }
            else {
                throw new Error(result.error || 'Failed to load configuration');
            }
        }
        catch (error) {
            console.error('Error loading configuration:', error);
            throw error;
        }
    }
    /**
     * Save configuration to backend
     */
    async saveConfig(config) {
        try {
            const result = await updateLsfgConfig(config);
            if (result.success) {
                this._config = config;
            }
            else {
                throw new Error(result.error || 'Failed to save configuration');
            }
        }
        catch (error) {
            console.error('Error saving configuration:', error);
            throw error;
        }
    }
    /**
     * Update a single configuration field
     */
    async updateField(fieldName, value) {
        if (!this._config) {
            await this.loadConfig();
        }
        const updatedConfig = {
            ...this._config,
            [fieldName]: value
        };
        await this.saveConfig(updatedConfig);
    }
    /**
     * Get current configuration (cached)
     */
    getConfig() {
        return this._config;
    }
    /**
     * Reset configuration to defaults
     */
    async resetToDefaults() {
        try {
            const result = await this.resetConfiguration();
            if (result.success && result.data) {
                this._config = result.data;
                return this._config;
            }
            else {
                throw new Error(result.error || 'Failed to reset configuration');
            }
        }
        catch (error) {
            console.error('Error resetting configuration:', error);
            throw error;
        }
    }
}
ConfigurationManager.getInstance();

/**
 * Centralized toast notification utilities
 * Provides consistent success/error messaging patterns
 */
/**
 * Show a success toast notification
 */
function showSuccessToast(title, body) {
    toaster.toast({
        title,
        body
    });
}
/**
 * Show an error toast notification
 */
function showErrorToast(title, body) {
    toaster.toast({
        title,
        body
    });
}
/**
 * Standard success messages for common operations
 */
const ToastMessages = {
    INSTALL_SUCCESS: {
        title: "Installation Complete",
        body: "lsfg-vk has been installed successfully"
    },
    INSTALL_ERROR: {
        title: "Installation Failed",
        body: "Unknown error occurred"
    },
    UNINSTALL_SUCCESS: {
        title: "Uninstallation Complete",
        body: "lsfg-vk has been uninstalled successfully"
    },
    UNINSTALL_ERROR: {
        title: "Uninstallation Failed",
        body: "Unknown error occurred"
    },
    CONFIG_UPDATE_ERROR: {
        title: "Update Failed",
        body: "Failed to update configuration"
    },
    CLIPBOARD_SUCCESS: {
        title: "Copied to Clipboard!",
        body: "Launch option ready to paste"
    },
    CLIPBOARD_ERROR: {
        title: "Copy Failed",
        body: "Unable to copy to clipboard"
    }
};
/**
 * Show installation success toast
 */
function showInstallSuccessToast() {
    showSuccessToast(ToastMessages.INSTALL_SUCCESS.title, ToastMessages.INSTALL_SUCCESS.body);
}
/**
 * Show installation error toast
 */
function showInstallErrorToast(error) {
    showErrorToast(ToastMessages.INSTALL_ERROR.title, error || ToastMessages.INSTALL_ERROR.body);
}
/**
 * Show uninstallation success toast
 */
function showUninstallSuccessToast() {
    showSuccessToast(ToastMessages.UNINSTALL_SUCCESS.title, ToastMessages.UNINSTALL_SUCCESS.body);
}
/**
 * Show uninstallation error toast
 */
function showUninstallErrorToast(error) {
    showErrorToast(ToastMessages.UNINSTALL_ERROR.title, error || ToastMessages.UNINSTALL_ERROR.body);
}
/**
 * Show clipboard error toast
 */
function showClipboardErrorToast() {
    showErrorToast(ToastMessages.CLIPBOARD_ERROR.title, ToastMessages.CLIPBOARD_ERROR.body);
}

function useInstallationStatus() {
    const [isInstalled, setIsInstalled] = SP_REACT.useState(false);
    const [installationStatus, setInstallationStatus] = SP_REACT.useState("");
    const checkInstallation = async () => {
        try {
            const status = await checkLsfgVkInstalled();
            setIsInstalled(status.installed);
            if (status.installed) {
                setInstallationStatus("lsfg-vk Installed");
            }
            else {
                setInstallationStatus("lsfg-vk Not Installed");
            }
            return status.installed;
        }
        catch (error) {
            setInstallationStatus("lsfg-vk Not Installed");
            return false;
        }
    };
    SP_REACT.useEffect(() => {
        checkInstallation();
    }, []);
    return {
        isInstalled,
        installationStatus,
        setIsInstalled,
        setInstallationStatus,
        checkInstallation
    };
}
function useDllDetection() {
    const [dllDetected, setDllDetected] = SP_REACT.useState(false);
    const [dllDetectionStatus, setDllDetectionStatus] = SP_REACT.useState("");
    const checkDllDetection = async () => {
        try {
            const result = await checkLosslessScalingDll();
            setDllDetected(result.detected);
            if (result.detected) {
                setDllDetectionStatus("Lossless Scaling Installed");
            }
            else {
                setDllDetectionStatus("Lossless Scaling Not Installed");
            }
        }
        catch (error) {
            setDllDetectionStatus("Lossless Scaling Not Installed");
        }
    };
    SP_REACT.useEffect(() => {
        checkDllDetection();
    }, []);
    return {
        dllDetected,
        dllDetectionStatus
    };
}
function useLsfgConfig() {
    const [config, setConfig] = SP_REACT.useState(() => ConfigurationManager.getDefaults());
    const loadLsfgConfig = SP_REACT.useCallback(async () => {
        try {
            const result = await getLsfgConfig();
            if (result.success && result.config) {
                setConfig(result.config);
            }
            else {
                console.log("lsfg config not available, using defaults:", result.error);
                setConfig(ConfigurationManager.getDefaults());
            }
        }
        catch (error) {
            console.error("Error loading lsfg config:", error);
            setConfig(ConfigurationManager.getDefaults());
        }
    }, []);
    const updateConfig = SP_REACT.useCallback(async (newConfig) => {
        try {
            const result = await updateLsfgConfigFromObject(newConfig);
            if (result.success) {
                setConfig(newConfig);
            }
            else {
                showErrorToast(ToastMessages.CONFIG_UPDATE_ERROR.title, result.error || ToastMessages.CONFIG_UPDATE_ERROR.body);
            }
            return result;
        }
        catch (error) {
            showErrorToast(ToastMessages.CONFIG_UPDATE_ERROR.title, String(error));
            return { success: false, error: String(error) };
        }
    }, []);
    const updateField = SP_REACT.useCallback(async (fieldName, value) => {
        const newConfig = { ...config, [fieldName]: value };
        return updateConfig(newConfig);
    }, [config, updateConfig]);
    SP_REACT.useEffect(() => {
        loadLsfgConfig();
    }, []);
    return {
        config,
        setConfig,
        loadLsfgConfig,
        updateConfig,
        updateField
    };
}

function useProfileManagement() {
    const [profiles, setProfiles] = SP_REACT.useState([]);
    const [currentProfile, setCurrentProfileState] = SP_REACT.useState("decky-lsfg-vk");
    const [isLoading, setIsLoading] = SP_REACT.useState(false);
    // Load profiles on hook initialization
    const loadProfiles = SP_REACT.useCallback(async () => {
        try {
            const result = await getProfiles();
            if (result.success && result.profiles) {
                setProfiles(result.profiles);
                if (result.current_profile) {
                    setCurrentProfileState(result.current_profile);
                }
                return result;
            }
            else {
                console.error("Failed to load profiles:", result.error);
                showErrorToast("Failed to load profiles", result.error || "Unknown error");
                return result;
            }
        }
        catch (error) {
            console.error("Error loading profiles:", error);
            showErrorToast("Error loading profiles", String(error));
            return { success: false, error: String(error) };
        }
    }, []);
    // Create a new profile
    const handleCreateProfile = SP_REACT.useCallback(async (profileName, sourceProfile) => {
        setIsLoading(true);
        try {
            const result = await createProfile(profileName, sourceProfile || currentProfile);
            if (result.success) {
                showSuccessToast("Profile created", `Created profile: ${profileName}`);
                await loadProfiles();
                return result;
            }
            else {
                console.error("Failed to create profile:", result.error);
                showErrorToast("Failed to create profile", result.error || "Unknown error");
                return result;
            }
        }
        catch (error) {
            console.error("Error creating profile:", error);
            showErrorToast("Error creating profile", String(error));
            return { success: false, error: String(error) };
        }
        finally {
            setIsLoading(false);
        }
    }, [currentProfile, loadProfiles]);
    // Delete a profile
    const handleDeleteProfile = SP_REACT.useCallback(async (profileName) => {
        if (profileName === "decky-lsfg-vk") {
            showErrorToast("Cannot delete default profile", "The default profile cannot be deleted");
            return { success: false, error: "Cannot delete default profile" };
        }
        setIsLoading(true);
        try {
            const result = await deleteProfile(profileName);
            if (result.success) {
                showSuccessToast("Profile deleted", `Deleted profile: ${profileName}`);
                await loadProfiles();
                // If we deleted the current profile, it should have switched to default
                if (currentProfile === profileName) {
                    setCurrentProfileState("decky-lsfg-vk");
                }
                return result;
            }
            else {
                console.error("Failed to delete profile:", result.error);
                showErrorToast("Failed to delete profile", result.error || "Unknown error");
                return result;
            }
        }
        catch (error) {
            console.error("Error deleting profile:", error);
            showErrorToast("Error deleting profile", String(error));
            return { success: false, error: String(error) };
        }
        finally {
            setIsLoading(false);
        }
    }, [currentProfile, loadProfiles]);
    // Rename a profile
    const handleRenameProfile = SP_REACT.useCallback(async (oldName, newName) => {
        if (oldName === "decky-lsfg-vk") {
            showErrorToast("Cannot rename default profile", "The default profile cannot be renamed");
            return { success: false, error: "Cannot rename default profile" };
        }
        setIsLoading(true);
        try {
            const result = await renameProfile(oldName, newName);
            if (result.success) {
                showSuccessToast("Profile renamed", `Renamed profile to: ${newName}`);
                await loadProfiles();
                // Update current profile if it was renamed
                if (currentProfile === oldName) {
                    setCurrentProfileState(newName);
                }
                return result;
            }
            else {
                console.error("Failed to rename profile:", result.error);
                showErrorToast("Failed to rename profile", result.error || "Unknown error");
                return result;
            }
        }
        catch (error) {
            console.error("Error renaming profile:", error);
            showErrorToast("Error renaming profile", String(error));
            return { success: false, error: String(error) };
        }
        finally {
            setIsLoading(false);
        }
    }, [currentProfile, loadProfiles]);
    // Set the current active profile
    const handleSetCurrentProfile = SP_REACT.useCallback(async (profileName) => {
        setIsLoading(true);
        try {
            const result = await setCurrentProfile(profileName);
            if (result.success) {
                setCurrentProfileState(profileName);
                showSuccessToast("Profile switched", `Switched to profile: ${profileName}`);
                return result;
            }
            else {
                console.error("Failed to switch profile:", result.error);
                showErrorToast("Failed to switch profile", result.error || "Unknown error");
                return result;
            }
        }
        catch (error) {
            console.error("Error switching profile:", error);
            showErrorToast("Error switching profile", String(error));
            return { success: false, error: String(error) };
        }
        finally {
            setIsLoading(false);
        }
    }, []);
    // Update configuration for a specific profile
    const handleUpdateProfileConfig = SP_REACT.useCallback(async (profileName, config) => {
        setIsLoading(true);
        try {
            const result = await updateProfileConfig(profileName, config);
            if (result.success) {
                return result;
            }
            else {
                console.error("Failed to update profile config:", result.error);
                showErrorToast("Failed to update profile config", result.error || "Unknown error");
                return result;
            }
        }
        catch (error) {
            console.error("Error updating profile config:", error);
            showErrorToast("Error updating profile config", String(error));
            return { success: false, error: String(error) };
        }
        finally {
            setIsLoading(false);
        }
    }, [currentProfile]);
    // Initialize profiles on mount
    SP_REACT.useEffect(() => {
        loadProfiles();
    }, [loadProfiles]);
    return {
        profiles,
        currentProfile,
        isLoading,
        loadProfiles,
        createProfile: handleCreateProfile,
        deleteProfile: handleDeleteProfile,
        renameProfile: handleRenameProfile,
        setCurrentProfile: handleSetCurrentProfile,
        updateProfileConfig: handleUpdateProfileConfig
    };
}

function useInstallationActions() {
    const [isInstalling, setIsInstalling] = SP_REACT.useState(false);
    const [isUninstalling, setIsUninstalling] = SP_REACT.useState(false);
    const handleInstall = async (setIsInstalled, setInstallationStatus, reloadConfig) => {
        setIsInstalling(true);
        setInstallationStatus("Installing lsfg-vk...");
        try {
            const result = await installLsfgVk();
            if (result.success) {
                setIsInstalled(true);
                setInstallationStatus("lsfg-vk installed");
                showInstallSuccessToast();
                // Reload lsfg config after installation
                if (reloadConfig) {
                    await reloadConfig();
                }
            }
            else {
                setInstallationStatus(`Installation failed: ${result.error}`);
                showInstallErrorToast(result.error);
            }
        }
        catch (error) {
            setInstallationStatus(`Installation failed: ${error}`);
            showInstallErrorToast(String(error));
        }
        finally {
            setIsInstalling(false);
        }
    };
    const handleUninstall = async (setIsInstalled, setInstallationStatus) => {
        setIsUninstalling(true);
        setInstallationStatus("Uninstalling lsfg-vk...");
        try {
            const result = await uninstallLsfgVk();
            if (result.success) {
                setIsInstalled(false);
                setInstallationStatus("lsfg-vk uninstalled successfully!");
                showUninstallSuccessToast();
            }
            else {
                setInstallationStatus(`Uninstallation failed: ${result.error}`);
                showUninstallErrorToast(result.error);
            }
        }
        catch (error) {
            setInstallationStatus(`Uninstallation failed: ${error}`);
            showUninstallErrorToast(String(error));
        }
        finally {
            setIsUninstalling(false);
        }
    };
    return {
        isInstalling,
        isUninstalling,
        handleInstall,
        handleUninstall
    };
}

function StatusDisplay({ dllDetected, dllDetectionStatus, isInstalled, installationStatus }) {
    return (window.SP_REACT.createElement(DFL.PanelSectionRow, null,
        window.SP_REACT.createElement("div", { style: { marginBottom: "8px", fontSize: "14px" } },
            window.SP_REACT.createElement("div", { style: {
                    color: dllDetected ? "#4CAF50" : "#F44336",
                    fontWeight: "600",
                    marginBottom: "6px",
                    display: "flex",
                    alignItems: "center",
                    gap: "6px"
                } },
                window.SP_REACT.createElement("span", { style: { fontSize: "16px" } }, dllDetected ? "✅" : "❌"),
                dllDetectionStatus),
            window.SP_REACT.createElement("div", { style: {
                    color: isInstalled ? "#4CAF50" : "#FF9800",
                    fontWeight: "600",
                    display: "flex",
                    alignItems: "center",
                    gap: "6px"
                } },
                window.SP_REACT.createElement("span", { style: { fontSize: "16px" } }, isInstalled ? "✅" : "❌"),
                installationStatus))));
}

// THIS FILE IS AUTO GENERATED
function FaCheck (props) {
  return GenIcon({"tag":"svg","attr":{"viewBox":"0 0 512 512"},"child":[{"tag":"path","attr":{"d":"M173.898 439.404l-166.4-166.4c-9.997-9.997-9.997-26.206 0-36.204l36.203-36.204c9.997-9.998 26.207-9.998 36.204 0L192 312.69 432.095 72.596c9.997-9.997 26.207-9.997 36.204 0l36.203 36.204c9.997 9.997 9.997 26.206 0 36.204l-294.4 294.401c-9.998 9.997-26.207 9.997-36.204-.001z"},"child":[]}]})(props);
}function FaClipboard (props) {
  return GenIcon({"tag":"svg","attr":{"viewBox":"0 0 384 512"},"child":[{"tag":"path","attr":{"d":"M384 112v352c0 26.51-21.49 48-48 48H48c-26.51 0-48-21.49-48-48V112c0-26.51 21.49-48 48-48h80c0-35.29 28.71-64 64-64s64 28.71 64 64h80c26.51 0 48 21.49 48 48zM192 40c-13.255 0-24 10.745-24 24s10.745 24 24 24 24-10.745 24-24-10.745-24-24-24m96 114v-20a6 6 0 0 0-6-6H102a6 6 0 0 0-6 6v20a6 6 0 0 0 6 6h180a6 6 0 0 0 6-6z"},"child":[]}]})(props);
}function FaCog (props) {
  return GenIcon({"tag":"svg","attr":{"viewBox":"0 0 512 512"},"child":[{"tag":"path","attr":{"d":"M487.4 315.7l-42.6-24.6c4.3-23.2 4.3-47 0-70.2l42.6-24.6c4.9-2.8 7.1-8.6 5.5-14-11.1-35.6-30-67.8-54.7-94.6-3.8-4.1-10-5.1-14.8-2.3L380.8 110c-17.9-15.4-38.5-27.3-60.8-35.1V25.8c0-5.6-3.9-10.5-9.4-11.7-36.7-8.2-74.3-7.8-109.2 0-5.5 1.2-9.4 6.1-9.4 11.7V75c-22.2 7.9-42.8 19.8-60.8 35.1L88.7 85.5c-4.9-2.8-11-1.9-14.8 2.3-24.7 26.7-43.6 58.9-54.7 94.6-1.7 5.4.6 11.2 5.5 14L67.3 221c-4.3 23.2-4.3 47 0 70.2l-42.6 24.6c-4.9 2.8-7.1 8.6-5.5 14 11.1 35.6 30 67.8 54.7 94.6 3.8 4.1 10 5.1 14.8 2.3l42.6-24.6c17.9 15.4 38.5 27.3 60.8 35.1v49.2c0 5.6 3.9 10.5 9.4 11.7 36.7 8.2 74.3 7.8 109.2 0 5.5-1.2 9.4-6.1 9.4-11.7v-49.2c22.2-7.9 42.8-19.8 60.8-35.1l42.6 24.6c4.9 2.8 11 1.9 14.8-2.3 24.7-26.7 43.6-58.9 54.7-94.6 1.5-5.5-.7-11.3-5.6-14.1zM256 336c-44.1 0-80-35.9-80-80s35.9-80 80-80 80 35.9 80 80-35.9 80-80 80z"},"child":[]}]})(props);
}function FaDownload (props) {
  return GenIcon({"tag":"svg","attr":{"viewBox":"0 0 512 512"},"child":[{"tag":"path","attr":{"d":"M216 0h80c13.3 0 24 10.7 24 24v168h87.7c17.8 0 26.7 21.5 14.1 34.1L269.7 378.3c-7.5 7.5-19.8 7.5-27.3 0L90.1 226.1c-12.6-12.6-3.7-34.1 14.1-34.1H192V24c0-13.3 10.7-24 24-24zm296 376v112c0 13.3-10.7 24-24 24H24c-13.3 0-24-10.7-24-24V376c0-13.3 10.7-24 24-24h146.7l49 49c20.1 20.1 52.5 20.1 72.6 0l49-49H488c13.3 0 24 10.7 24 24zm-124 88c0-11-9-20-20-20s-20 9-20 20 9 20 20 20 20-9 20-20zm64 0c0-11-9-20-20-20s-20 9-20 20 9 20 20 20 20-9 20-20z"},"child":[]}]})(props);
}function FaTimes (props) {
  return GenIcon({"tag":"svg","attr":{"viewBox":"0 0 352 512"},"child":[{"tag":"path","attr":{"d":"M242.72 256l100.07-100.07c12.28-12.28 12.28-32.19 0-44.48l-22.24-22.24c-12.28-12.28-32.19-12.28-44.48 0L176 189.28 75.93 89.21c-12.28-12.28-32.19-12.28-44.48 0L9.21 111.45c-12.28 12.28-12.28 32.19 0 44.48L109.28 256 9.21 356.07c-12.28 12.28-12.28 32.19 0 44.48l22.24 22.24c12.28 12.28 32.2 12.28 44.48 0L176 322.72l100.07 100.07c12.28 12.28 32.2 12.28 44.48 0l22.24-22.24c12.28-12.28 12.28-32.19 0-44.48L242.72 256z"},"child":[]}]})(props);
}function FaTrash (props) {
  return GenIcon({"tag":"svg","attr":{"viewBox":"0 0 448 512"},"child":[{"tag":"path","attr":{"d":"M432 32H312l-9.4-18.7A24 24 0 0 0 281.1 0H166.8a23.72 23.72 0 0 0-21.4 13.3L136 32H16A16 16 0 0 0 0 48v32a16 16 0 0 0 16 16h416a16 16 0 0 0 16-16V48a16 16 0 0 0-16-16zM53.2 467a48 48 0 0 0 47.9 45h245.8a48 48 0 0 0 47.9-45L416 128H32z"},"child":[]}]})(props);
}

function InstallationButton({ isInstalled, isInstalling, isUninstalling, onInstall, onUninstall }) {
    const renderButtonContent = () => {
        if (isInstalling) {
            return (window.SP_REACT.createElement("div", { style: { display: "flex", alignItems: "center", gap: "8px" } },
                window.SP_REACT.createElement("div", null, "Installing...")));
        }
        if (isUninstalling) {
            return (window.SP_REACT.createElement("div", { style: { display: "flex", alignItems: "center", gap: "8px" } },
                window.SP_REACT.createElement("div", null, "Uninstalling...")));
        }
        if (isInstalled) {
            return (window.SP_REACT.createElement("div", { style: { display: "flex", alignItems: "center", gap: "8px" } },
                window.SP_REACT.createElement(FaTrash, null),
                window.SP_REACT.createElement("div", null, "Uninstall LSFG-VK")));
        }
        return (window.SP_REACT.createElement("div", { style: { display: "flex", alignItems: "center", gap: "8px" } },
            window.SP_REACT.createElement(FaDownload, null),
            window.SP_REACT.createElement("div", null, "Install LSFG-VK")));
    };
    return (window.SP_REACT.createElement(DFL.PanelSectionRow, null,
        window.SP_REACT.createElement(DFL.ButtonItem, { layout: "below", onClick: isInstalled ? onUninstall : onInstall, disabled: isInstalling || isUninstalling }, renderButtonContent())));
}

// THIS FILE IS AUTO GENERATED
function RiArrowDownSFill (props) {
  return GenIcon({"tag":"svg","attr":{"viewBox":"0 0 24 24","fill":"currentColor"},"child":[{"tag":"path","attr":{"d":"M12 16L6 10H18L12 16Z"},"child":[]}]})(props);
}function RiArrowUpSFill (props) {
  return GenIcon({"tag":"svg","attr":{"viewBox":"0 0 24 24","fill":"currentColor"},"child":[{"tag":"path","attr":{"d":"M12 8L18 14H6L12 8Z"},"child":[]}]})(props);
}function RiEditLine (props) {
  return GenIcon({"tag":"svg","attr":{"viewBox":"0 0 24 24","fill":"currentColor"},"child":[{"tag":"path","attr":{"d":"M6.41421 15.89L16.5563 5.74785L15.1421 4.33363L5 14.4758V15.89H6.41421ZM7.24264 17.89H3V13.6473L14.435 2.21231C14.8256 1.82179 15.4587 1.82179 15.8492 2.21231L18.6777 5.04074C19.0682 5.43126 19.0682 6.06443 18.6777 6.45495L7.24264 17.89ZM3 19.89H21V21.89H3V19.89Z"},"child":[]}]})(props);
}function RiDeleteBinLine (props) {
  return GenIcon({"tag":"svg","attr":{"viewBox":"0 0 24 24","fill":"currentColor"},"child":[{"tag":"path","attr":{"d":"M17 6H22V8H20V21C20 21.5523 19.5523 22 19 22H5C4.44772 22 4 21.5523 4 21V8H2V6H7V3C7 2.44772 7.44772 2 8 2H16C16.5523 2 17 2.44772 17 3V6ZM18 8H6V20H18V8ZM9 11H11V17H9V11ZM13 11H15V17H13V11ZM9 4V6H15V4H9Z"},"child":[]}]})(props);
}

const WORKAROUNDS_COLLAPSED_KEY = "lsfg-workarounds-collapsed";
const CONFIG_COLLAPSED_KEY = "lsfg-config-collapsed";
function ConfigurationSection({ config, onConfigChange }) {
    // Initialize with localStorage value, fallback to true if not found
    const [configCollapsed, setConfigCollapsed] = SP_REACT.useState(() => {
        try {
            const saved = localStorage.getItem(CONFIG_COLLAPSED_KEY);
            return saved !== null ? JSON.parse(saved) : false;
        }
        catch {
            return false;
        }
    });
    const [workaroundsCollapsed, setWorkaroundsCollapsed] = SP_REACT.useState(() => {
        try {
            const saved = localStorage.getItem(WORKAROUNDS_COLLAPSED_KEY);
            return saved !== null ? JSON.parse(saved) : true;
        }
        catch {
            return true;
        }
    });
    // Persist workarounds collapse state to localStorage
    SP_REACT.useEffect(() => {
        try {
            localStorage.setItem(CONFIG_COLLAPSED_KEY, JSON.stringify(configCollapsed));
        }
        catch (error) {
            console.warn("Failed to save config collapse state:", error);
        }
    }, [configCollapsed]);
    SP_REACT.useEffect(() => {
        try {
            localStorage.setItem(WORKAROUNDS_COLLAPSED_KEY, JSON.stringify(workaroundsCollapsed));
        }
        catch (error) {
            console.warn("Failed to save workarounds collapse state:", error);
        }
    }, [workaroundsCollapsed]);
    return (window.SP_REACT.createElement(window.SP_REACT.Fragment, null,
        window.SP_REACT.createElement("style", null, `
        .LSFG_ConfigCollapseButton_Container > div > div > div > button,
        .LSFG_ConfigCollapseButton_Container > div > div > div > div > button,
        .LSFG_WorkaroundsCollapseButton_Container > div > div > div > button {
          height: 10px !important;
        }
        .LSFG_WorkaroundsCollapseButton_Container > div > div > div > div > button {
          height: 10px !important;
        }
        `),
        window.SP_REACT.createElement(DFL.PanelSectionRow, null,
            window.SP_REACT.createElement("div", { style: {
                    fontSize: "14px",
                    fontWeight: "bold",
                    marginTop: "8px",
                    marginBottom: "6px",
                    borderBottom: "1px solid rgba(255, 255, 255, 0.2)",
                    paddingBottom: "3px",
                    color: "white"
                } }, "Config")),
        window.SP_REACT.createElement(DFL.PanelSectionRow, null,
            window.SP_REACT.createElement("div", { className: "LSFG_ConfigCollapseButton_Container", style: { marginTop: "-2px", marginBottom: "4px" } },
                window.SP_REACT.createElement(DFL.ButtonItem, { layout: "below", bottomSeparator: configCollapsed ? "standard" : "none", onClick: () => setConfigCollapsed(!configCollapsed) }, configCollapsed ? (window.SP_REACT.createElement(RiArrowDownSFill, { style: { transform: "translate(0, -13px)", fontSize: "1.5em" } })) : (window.SP_REACT.createElement(RiArrowUpSFill, { style: { transform: "translate(0, -12px)", fontSize: "1.5em" } }))))),
        !configCollapsed && (window.SP_REACT.createElement(window.SP_REACT.Fragment, null,
            window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                window.SP_REACT.createElement(DFL.SliderField, { label: `Flow Scale (${Math.round(config.flow_scale * 100)}%)`, description: "Lowers internal motion estimation resolution, improving performance slightly", value: config.flow_scale, min: 0.25, max: 1.0, step: 0.01, onChange: (value) => onConfigChange(FLOW_SCALE, value) })),
            window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                window.SP_REACT.createElement(DFL.SliderField, { label: `Base FPS Cap${config.dxvk_frame_rate > 0 ? ` (${config.dxvk_frame_rate} FPS)` : " (Off)"}`, description: "Base framerate cap for DirectX games, before frame multiplier. (Requires game restart to apply)", value: config.dxvk_frame_rate, min: 0, max: 60, step: 1, onChange: (value) => onConfigChange(DXVK_FRAME_RATE, value) })),
            window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                window.SP_REACT.createElement(DFL.ToggleField, { label: `Present Mode (${(config.experimental_present_mode || "fifo") === "fifo" ? "FIFO - VSync" : "Mailbox"})`, description: "Toggle between FIFO - VSync (default) and Mailbox presentation modes for better performance or compatibility", checked: (config.experimental_present_mode || "fifo") === "fifo", onChange: (value) => onConfigChange(EXPERIMENTAL_PRESENT_MODE, value ? "fifo" : "mailbox") })),
            window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                window.SP_REACT.createElement(DFL.ToggleField, { label: "Performance Mode", description: "Uses a lighter model for FG (Recommended for most games)", checked: config.performance_mode, onChange: (value) => onConfigChange(PERFORMANCE_MODE, value) })),
            window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                window.SP_REACT.createElement(DFL.ToggleField, { label: "HDR Mode", description: "Enables HDR mode (only for games that support HDR)", checked: config.hdr_mode, onChange: (value) => onConfigChange(HDR_MODE, value) })))),
        window.SP_REACT.createElement(DFL.PanelSectionRow, null,
            window.SP_REACT.createElement("div", { style: {
                    fontSize: "14px",
                    fontWeight: "bold",
                    marginTop: "8px",
                    marginBottom: "6px",
                    borderBottom: "1px solid rgba(255, 255, 255, 0.2)",
                    paddingBottom: "3px",
                    color: "white"
                } }, "Workarounds")),
        window.SP_REACT.createElement(DFL.PanelSectionRow, null,
            window.SP_REACT.createElement("div", { className: "LSFG_WorkaroundsCollapseButton_Container", style: { marginTop: "-2px", marginBottom: "4px" } },
                window.SP_REACT.createElement(DFL.ButtonItem, { layout: "below", bottomSeparator: workaroundsCollapsed ? "standard" : "none", onClick: () => setWorkaroundsCollapsed(!workaroundsCollapsed) }, workaroundsCollapsed ? (window.SP_REACT.createElement(RiArrowDownSFill, { style: { transform: "translate(0, -13px)", fontSize: "1.5em" } })) : (window.SP_REACT.createElement(RiArrowUpSFill, { style: { transform: "translate(0, -12px)", fontSize: "1.5em" } }))))),
        !workaroundsCollapsed && (window.SP_REACT.createElement(window.SP_REACT.Fragment, null,
            window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                window.SP_REACT.createElement(DFL.ToggleField, { label: "Enable WSI", description: "Re-Enable Gamescope WSI Layer. Requires game restart to apply.", checked: config.enable_wsi, onChange: (value) => onConfigChange(ENABLE_WSI, value) })),
            window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                window.SP_REACT.createElement(DFL.ToggleField, { label: "Enable WOW64 for 32-bit games", description: "Enables PROTON_USE_WOW64=1 for 32-bit games (Use with ProtonGE to fix crashing)", checked: config.enable_wow64, onChange: (value) => onConfigChange('enable_wow64', value) })),
            window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                window.SP_REACT.createElement(DFL.ToggleField, { label: "Disable Steam Deck Mode", description: "Disables Steam Deck mode (Unlocks hidden settings in some games)", checked: config.disable_steamdeck_mode, onChange: (value) => onConfigChange(DISABLE_STEAMDECK_MODE, value) })),
            window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                window.SP_REACT.createElement(DFL.ToggleField, { label: "MangoHud Workaround", description: "Enables a transparent mangohud overlay, sometimes fixes issues with 2X multiplier in game mode", checked: config.mangohud_workaround, onChange: (value) => onConfigChange(MANGOHUD_WORKAROUND, value) })),
            window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                window.SP_REACT.createElement(DFL.ToggleField, { label: "Disable vkBasalt", description: "Disables vkBasalt layer which can conflict with LSFG (Reshade, some Decky plugins)", checked: config.disable_vkbasalt, disabled: config.force_enable_vkbasalt, onChange: (value) => {
                        if (value && config.force_enable_vkbasalt) {
                            // Turn off force enable when enabling disable
                            onConfigChange(FORCE_ENABLE_VKBASALT, false);
                        }
                        onConfigChange(DISABLE_VKBASALT, value);
                    } })),
            window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                window.SP_REACT.createElement(DFL.ToggleField, { label: "Force Enable vkBasalt", description: "Force vkBasalt to engage to fix framepacing issues in gamemode", checked: config.force_enable_vkbasalt, disabled: config.disable_vkbasalt, onChange: (value) => {
                        if (value && config.disable_vkbasalt) {
                            // Turn off disable when enabling force enable
                            onConfigChange(DISABLE_VKBASALT, false);
                        }
                        onConfigChange(FORCE_ENABLE_VKBASALT, value);
                    } })),
            window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                window.SP_REACT.createElement(DFL.ToggleField, { label: "Enable Zink for OpenGL Games", description: "Use Vulkan-based OpenGL implementation for OpenGL games (may cause crashes or freezes with some games)", checked: config.enable_zink, onChange: (value) => onConfigChange(ENABLE_ZINK, value) }))))));
}

const PROFILES_COLLAPSED_KEY = 'lsfg-profiles-collapsed';
function TextInputModal({ title, description, defaultValue = "", okText = "OK", cancelText = "Cancel", onOK, closeModal }) {
    const [value, setValue] = SP_REACT.useState(defaultValue);
    const handleOK = () => {
        if (value.trim()) {
            onOK(value);
            closeModal?.();
        }
    };
    return (window.SP_REACT.createElement(DFL.ModalRoot, null,
        window.SP_REACT.createElement("div", { style: { padding: "16px", minWidth: "400px" } },
            window.SP_REACT.createElement("h2", { style: { marginBottom: "16px" } }, title),
            window.SP_REACT.createElement("p", { style: { marginBottom: "24px" } }, description),
            window.SP_REACT.createElement("div", { style: { marginBottom: "24px" } },
                window.SP_REACT.createElement(DFL.Field, { label: "Name", childrenLayout: "below", childrenContainerWidth: "max" },
                    window.SP_REACT.createElement(DFL.TextField, { value: value, onChange: (e) => setValue(e?.target?.value || ""), style: { width: "100%" } }))),
            window.SP_REACT.createElement(DFL.Focusable, { style: {
                    display: "flex",
                    justifyContent: "flex-end",
                    gap: "8px",
                    marginTop: "16px"
                }, "flow-children": "horizontal" },
                window.SP_REACT.createElement(DFL.DialogButton, { onClick: closeModal }, cancelText),
                window.SP_REACT.createElement(DFL.DialogButton, { onClick: handleOK, disabled: !value.trim() }, okText)))));
}
function ProfileManagement({ currentProfile, onProfileChange }) {
    const [profiles, setProfiles] = SP_REACT.useState([]);
    const [selectedProfile, setSelectedProfile] = SP_REACT.useState(currentProfile || "decky-lsfg-vk");
    const [isLoading, setIsLoading] = SP_REACT.useState(false);
    const [mainRunningApp, setMainRunningApp] = SP_REACT.useState(undefined);
    // Initialize with localStorage value, fallback to false (expanded) if not found
    const [profilesCollapsed, setProfilesCollapsed] = SP_REACT.useState(() => {
        try {
            const saved = localStorage.getItem(PROFILES_COLLAPSED_KEY);
            return saved !== null ? JSON.parse(saved) : false;
        }
        catch {
            return false;
        }
    });
    // Persist profiles collapse state to localStorage
    SP_REACT.useEffect(() => {
        try {
            localStorage.setItem(PROFILES_COLLAPSED_KEY, JSON.stringify(profilesCollapsed));
        }
        catch (error) {
            console.warn('Failed to save profiles collapse state:', error);
        }
    }, [profilesCollapsed]);
    // Load profiles on component mount
    SP_REACT.useEffect(() => {
        loadProfiles();
    }, []);
    // Update selected profile when prop changes
    SP_REACT.useEffect(() => {
        if (currentProfile) {
            setSelectedProfile(currentProfile);
        }
    }, [currentProfile]);
    // Poll for running app every 2 seconds
    SP_REACT.useEffect(() => {
        const checkRunningApp = () => {
            setMainRunningApp(DFL.Router.MainRunningApp);
        };
        // Check immediately
        checkRunningApp();
        // Set up polling interval
        const interval = setInterval(checkRunningApp, 2000);
        // Cleanup interval on unmount
        return () => clearInterval(interval);
    }, []);
    const loadProfiles = async () => {
        try {
            const result = await getProfiles();
            if (result.success && result.profiles) {
                setProfiles(result.profiles);
                if (result.current_profile) {
                    setSelectedProfile(result.current_profile);
                }
            }
            else {
                console.error("Failed to load profiles:", result.error);
                showErrorToast("Failed to load profiles", result.error || "Unknown error");
            }
        }
        catch (error) {
            console.error("Error loading profiles:", error);
            showErrorToast("Error loading profiles", String(error));
        }
    };
    const handleProfileChange = async (profileName) => {
        setIsLoading(true);
        try {
            const result = await setCurrentProfile(profileName);
            if (result.success) {
                setSelectedProfile(profileName);
                showSuccessToast("Profile switched", `Switched to profile: ${profileName}`);
                onProfileChange?.(profileName);
            }
            else {
                console.error("Failed to switch profile:", result.error);
                showErrorToast("Failed to switch profile", result.error || "Unknown error");
            }
        }
        catch (error) {
            console.error("Error switching profile:", error);
            showErrorToast("Error switching profile", String(error));
        }
        finally {
            setIsLoading(false);
        }
    };
    const handleCreateProfile = () => {
        DFL.showModal(window.SP_REACT.createElement(TextInputModal, { title: "Create New Profile", description: "Enter a name for the new profile. The current profile's settings will be copied.", okText: "Create", cancelText: "Cancel", onOK: (name) => {
                if (name.trim()) {
                    createNewProfile(name.trim());
                }
            } }));
    };
    const createNewProfile = async (profileName) => {
        setIsLoading(true);
        try {
            const result = await createProfile(profileName, selectedProfile);
            if (result.success) {
                showSuccessToast("Profile created", `Created profile: ${profileName}`);
                await loadProfiles();
                // Automatically switch to the newly created profile
                await handleProfileChange(profileName);
            }
            else {
                console.error("Failed to create profile:", result.error);
                showErrorToast("Failed to create profile", result.error || "Unknown error");
            }
        }
        catch (error) {
            console.error("Error creating profile:", error);
            showErrorToast("Error creating profile", String(error));
        }
        finally {
            setIsLoading(false);
        }
    };
    const handleDeleteProfile = () => {
        if (selectedProfile === "decky-lsfg-vk") {
            showErrorToast("Cannot delete default profile", "The default profile cannot be deleted");
            return;
        }
        DFL.showModal(window.SP_REACT.createElement(DFL.ConfirmModal, { strTitle: "Delete Profile", strDescription: `Are you sure you want to delete the profile "${selectedProfile}"? This action cannot be undone.`, strOKButtonText: "Delete", strCancelButtonText: "Cancel", onOK: () => deleteSelectedProfile() }));
    };
    const deleteSelectedProfile = async () => {
        setIsLoading(true);
        try {
            const result = await deleteProfile(selectedProfile);
            if (result.success) {
                showSuccessToast("Profile deleted", `Deleted profile: ${selectedProfile}`);
                await loadProfiles();
                // If we deleted the current profile, it should have switched to default
                setSelectedProfile("decky-lsfg-vk");
                onProfileChange?.("decky-lsfg-vk");
            }
            else {
                console.error("Failed to delete profile:", result.error);
                showErrorToast("Failed to delete profile", result.error || "Unknown error");
            }
        }
        catch (error) {
            console.error("Error deleting profile:", error);
            showErrorToast("Error deleting profile", String(error));
        }
        finally {
            setIsLoading(false);
        }
    };
    const handleDropdownChange = (option) => {
        if (option.data === "__NEW_PROFILE__") {
            handleCreateProfile();
        }
        else {
            handleProfileChange(option.data);
        }
    };
    const handleRenameProfile = () => {
        if (selectedProfile === "decky-lsfg-vk") {
            showErrorToast("Cannot rename default profile", "The default profile cannot be renamed");
            return;
        }
        DFL.showModal(window.SP_REACT.createElement(TextInputModal, { title: "Rename Profile", description: `Enter a new name for the profile "${selectedProfile}".`, defaultValue: selectedProfile, okText: "Rename", cancelText: "Cancel", onOK: (newName) => {
                if (newName.trim() && newName.trim() !== selectedProfile) {
                    renameSelectedProfile(newName.trim());
                }
            } }));
    };
    const renameSelectedProfile = async (newName) => {
        setIsLoading(true);
        try {
            const result = await renameProfile(selectedProfile, newName);
            if (result.success) {
                showSuccessToast("Profile renamed", `Renamed profile to: ${newName}`);
                await loadProfiles();
                setSelectedProfile(newName);
                onProfileChange?.(newName);
            }
            else {
                console.error("Failed to rename profile:", result.error);
                showErrorToast("Failed to rename profile", result.error || "Unknown error");
            }
        }
        catch (error) {
            console.error("Error renaming profile:", error);
            showErrorToast("Error renaming profile", String(error));
        }
        finally {
            setIsLoading(false);
        }
    };
    const profileOptions = [
        ...profiles.map((profile) => ({
            data: profile,
            label: profile === "decky-lsfg-vk" ? "Default" : profile
        })),
        {
            data: "__NEW_PROFILE__",
            label: "New Profile"
        }
    ];
    return (window.SP_REACT.createElement(window.SP_REACT.Fragment, null,
        window.SP_REACT.createElement("style", null, `
        .LSFG_ProfilesCollapseButton_Container > div > div > div > button {
          height: 10px !important;
        }
        .LSFG_ProfilesCollapseButton_Container > div > div > div > div > button {
          height: 10px !important;
        }
        `),
        mainRunningApp && (window.SP_REACT.createElement(DFL.PanelSectionRow, null,
            window.SP_REACT.createElement("div", { style: {
                    padding: "8px 12px",
                    backgroundColor: "rgba(0, 255, 0, 0.1)",
                    borderRadius: "4px",
                    border: "1px solid rgba(0, 255, 0, 0.3)",
                    fontSize: "13px"
                } },
                window.SP_REACT.createElement("strong", null, mainRunningApp.display_name),
                " running. Close game to change profile."))),
        window.SP_REACT.createElement(DFL.PanelSectionRow, null,
            window.SP_REACT.createElement("div", { style: {
                    fontSize: "14px",
                    fontWeight: "bold",
                    marginTop: "8px",
                    marginBottom: "6px",
                    borderBottom: "1px solid rgba(255, 255, 255, 0.2)",
                    paddingBottom: "3px",
                    color: "white"
                } },
                "Profile: ",
                selectedProfile === "decky-lsfg-vk" ? "Default" : selectedProfile)),
        window.SP_REACT.createElement(DFL.PanelSectionRow, null,
            window.SP_REACT.createElement("div", { className: "LSFG_ProfilesCollapseButton_Container", style: { marginTop: "-2px", marginBottom: "4px" } },
                window.SP_REACT.createElement(DFL.ButtonItem, { layout: "below", bottomSeparator: profilesCollapsed ? "standard" : "none", onClick: () => setProfilesCollapsed(!profilesCollapsed) }, profilesCollapsed ? (window.SP_REACT.createElement(RiArrowDownSFill, { style: { transform: "translate(0, -13px)", fontSize: "1.5em" } })) : (window.SP_REACT.createElement(RiArrowUpSFill, { style: { transform: "translate(0, -12px)", fontSize: "1.5em" } }))))),
        !profilesCollapsed && (window.SP_REACT.createElement(window.SP_REACT.Fragment, null,
            window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                window.SP_REACT.createElement(DFL.Field, { label: "", childrenLayout: "below", childrenContainerWidth: "max", bottomSeparator: "none" },
                    window.SP_REACT.createElement(DFL.Dropdown, { rgOptions: profileOptions, selectedOption: selectedProfile, onChange: handleDropdownChange, disabled: isLoading || !!mainRunningApp }))),
            window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                window.SP_REACT.createElement(DFL.Focusable, { style: {
                        display: "flex",
                        alignItems: "center",
                        gap: "8px",
                        width: "100%",
                        padding: "0",
                        margin: "0",
                        marginTop: "8px"
                    }, "flow-children": "horizontal" },
                    window.SP_REACT.createElement(DFL.DialogButton, { style: {
                            height: "40px",
                            flex: 1,
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "center",
                            padding: "10px",
                            minWidth: "0",
                        }, onClick: handleRenameProfile, disabled: isLoading || selectedProfile === "decky-lsfg-vk" || !!mainRunningApp },
                        window.SP_REACT.createElement(RiEditLine, { size: 20 })),
                    window.SP_REACT.createElement(DFL.DialogButton, { style: {
                            height: "40px",
                            flex: 1,
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "center",
                            padding: "10px",
                            minWidth: "0",
                        }, onClick: handleDeleteProfile, disabled: isLoading || selectedProfile === "decky-lsfg-vk" || !!mainRunningApp },
                        window.SP_REACT.createElement(RiDeleteBinLine, { size: 20 }))))))));
}

function UsageInstructions({ config: _config }) {
    return (window.SP_REACT.createElement(window.SP_REACT.Fragment, null,
        window.SP_REACT.createElement(DFL.PanelSectionRow, null,
            window.SP_REACT.createElement("div", { style: {
                    fontSize: "14px",
                    fontWeight: "bold",
                    marginTop: "16px",
                    marginBottom: "8px",
                    borderBottom: "1px solid rgba(255, 255, 255, 0.2)",
                    paddingBottom: "4px",
                    color: "white"
                } }, "Usage Instructions")),
        window.SP_REACT.createElement(DFL.PanelSectionRow, null,
            window.SP_REACT.createElement("div", { style: {
                    fontSize: "12px",
                    lineHeight: "1.4",
                    opacity: "0.8",
                    whiteSpace: "pre-wrap"
                } }, "Click \"Copy Launch Option\" button, then paste it into your Steam game's launch options to enable frame generation.")),
        window.SP_REACT.createElement(DFL.PanelSectionRow, null,
            window.SP_REACT.createElement("div", { style: {
                    fontSize: "12px",
                    lineHeight: "1.4",
                    opacity: "0.8",
                    backgroundColor: "rgba(255, 255, 255, 0.1)",
                    padding: "8px",
                    borderRadius: "4px",
                    fontFamily: "monospace",
                    marginTop: "8px",
                    marginBottom: "8px",
                    textAlign: "center"
                } },
                window.SP_REACT.createElement("strong", null, "~/lsfg %command%"))),
        window.SP_REACT.createElement(DFL.PanelSectionRow, null,
            window.SP_REACT.createElement("div", { style: {
                    fontSize: "11px",
                    lineHeight: "1.3",
                    opacity: "0.6",
                    marginTop: "8px"
                } }, "The configuration is stored in ~/.config/lsfg-vk/conf.toml and hot-reloads while games are running."))));
}

/**
 * Clipboard utilities for reliable copy operations across different environments
 */
/**
 * Reliably copy text to clipboard using multiple fallback methods
 * This is especially important in gaming mode where clipboard APIs may behave differently
 */
async function copyToClipboard(text) {
    const tempInput = document.createElement('input');
    tempInput.value = text;
    tempInput.style.position = 'absolute';
    tempInput.style.left = '-9999px';
    document.body.appendChild(tempInput);
    try {
        tempInput.focus();
        tempInput.select();
        let copySuccess = false;
        try {
            if (document.execCommand('copy')) {
                copySuccess = true;
            }
        }
        catch (e) {
            try {
                await navigator.clipboard.writeText(text);
                copySuccess = true;
            }
            catch (clipboardError) {
                console.error('Both copy methods failed:', e, clipboardError);
            }
        }
        return copySuccess;
    }
    finally {
        document.body.removeChild(tempInput);
    }
}
/**
 * Verify that text was successfully copied to clipboard
 */
async function verifyCopy(expectedText) {
    try {
        const readBack = await navigator.clipboard.readText();
        return readBack === expectedText;
    }
    catch (e) {
        return true;
    }
}
/**
 * Copy text with verification and return success status
 */
async function copyWithVerification(text) {
    const copySuccess = await copyToClipboard(text);
    if (!copySuccess) {
        return { success: false, verified: false };
    }
    const verified = await verifyCopy(text);
    return { success: true, verified };
}

function SmartClipboardButton() {
    const [isLoading, setIsLoading] = SP_REACT.useState(false);
    const [showSuccess, setShowSuccess] = SP_REACT.useState(false);
    SP_REACT.useEffect(() => {
        if (showSuccess) {
            const timer = setTimeout(() => {
                setShowSuccess(false);
            }, 3000);
            return () => clearTimeout(timer);
        }
        return undefined;
    }, [showSuccess]);
    const getLaunchOptionText = async () => {
        try {
            const result = await getLaunchOption();
            return result.launch_option || "~/lsfg %command%";
        }
        catch (error) {
            return "~/lsfg %command%";
        }
    };
    const copyToClipboard = async () => {
        if (isLoading || showSuccess)
            return;
        setIsLoading(true);
        try {
            const text = await getLaunchOptionText();
            const { success, verified } = await copyWithVerification(text);
            if (success) {
                setShowSuccess(true);
                if (!verified) {
                    console.log('Copy verification failed but copy likely worked');
                }
            }
            else {
                showClipboardErrorToast();
            }
        }
        catch (error) {
            showClipboardErrorToast();
        }
        finally {
            setIsLoading(false);
        }
    };
    return (window.SP_REACT.createElement(DFL.PanelSectionRow, null,
        window.SP_REACT.createElement(DFL.ButtonItem, { layout: "below", onClick: copyToClipboard, disabled: isLoading || showSuccess },
            window.SP_REACT.createElement("div", { style: { display: "flex", alignItems: "center", gap: "8px" } },
                showSuccess ? (window.SP_REACT.createElement(FaCheck, { style: { color: "#4CAF50" } })) : isLoading ? (window.SP_REACT.createElement(FaClipboard, { style: {
                        animation: "pulse 1s ease-in-out infinite",
                        opacity: 0.7
                    } })) : (window.SP_REACT.createElement(FaClipboard, null)),
                window.SP_REACT.createElement("div", { style: {
                        color: showSuccess ? "#4CAF50" : "inherit",
                        fontWeight: showSuccess ? "bold" : "normal"
                    } }, showSuccess ? "Copied to clipboard" : isLoading ? "Copying..." : "Copy Launch Option"))),
        window.SP_REACT.createElement("style", null, `
        @keyframes pulse {
          0% { opacity: 0.7; }
          50% { opacity: 1; }
          100% { opacity: 0.7; }
        }
      `)));
}

function FgmodClipboardButton() {
    const [isLoading, setIsLoading] = SP_REACT.useState(false);
    const [showSuccess, setShowSuccess] = SP_REACT.useState(false);
    const [fgmodExists, setFgmodExists] = SP_REACT.useState(false);
    const [checkingFgmod, setCheckingFgmod] = SP_REACT.useState(true);
    // Check for fgmod directory on component mount
    SP_REACT.useEffect(() => {
        const checkFgmod = async () => {
            try {
                const result = await checkFgmodDirectory();
                setFgmodExists(result.exists);
            }
            catch (error) {
                console.error("Error checking fgmod directory:", error);
                setFgmodExists(false);
            }
            finally {
                setCheckingFgmod(false);
            }
        };
        checkFgmod();
    }, []);
    // Reset success state after 3 seconds
    SP_REACT.useEffect(() => {
        if (showSuccess) {
            const timer = setTimeout(() => {
                setShowSuccess(false);
            }, 3000);
            return () => clearTimeout(timer);
        }
        return undefined;
    }, [showSuccess]);
    const copyToClipboard = async () => {
        if (isLoading || showSuccess)
            return;
        setIsLoading(true);
        try {
            const text = "~/fgmod/fgmod ~/lsfg %command%";
            const { success, verified } = await copyWithVerification(text);
            if (success) {
                // Show success feedback in the button instead of toast
                setShowSuccess(true);
                if (!verified) {
                    // Copy worked but verification failed - still show success
                    console.log('Copy verification failed but copy likely worked');
                }
            }
            else {
                showClipboardErrorToast();
            }
        }
        catch (error) {
            showClipboardErrorToast();
        }
        finally {
            setIsLoading(false);
        }
    };
    // Don't render if fgmod directory doesn't exist or we're still checking
    if (checkingFgmod || !fgmodExists) {
        return null;
    }
    return (window.SP_REACT.createElement(DFL.PanelSectionRow, null,
        window.SP_REACT.createElement(DFL.ButtonItem, { layout: "below", onClick: copyToClipboard, disabled: isLoading || showSuccess },
            window.SP_REACT.createElement("div", { style: { display: "flex", alignItems: "center", gap: "8px" } },
                showSuccess ? (window.SP_REACT.createElement(FaCheck, { style: {
                        color: "#4CAF50" // Green color for success
                    } })) : isLoading ? (window.SP_REACT.createElement(FaClipboard, { style: {
                        animation: "pulse 1s ease-in-out infinite",
                        opacity: 0.7
                    } })) : (window.SP_REACT.createElement(FaClipboard, null)),
                window.SP_REACT.createElement("div", { style: {
                        color: showSuccess ? "#4CAF50" : "inherit",
                        fontWeight: showSuccess ? "bold" : "normal"
                    } }, showSuccess ? "Copied to clipboard" : isLoading ? "Copying..." : "LSFG + DeckyFG"))),
        window.SP_REACT.createElement("style", null, `
        @keyframes pulse {
          0% { opacity: 0.7; }
          50% { opacity: 1; }
          100% { opacity: 0.7; }
        }
      `)));
}

function FpsMultiplierControl({ config, onConfigChange }) {
    return (window.SP_REACT.createElement(DFL.PanelSectionRow, null,
        window.SP_REACT.createElement(DFL.Focusable, { style: {
                marginTop: "6px",
                marginBottom: "6px",
                display: "flex",
                justifyContent: "center",
                alignItems: "center"
            }, "flow-children": "horizontal" },
            window.SP_REACT.createElement(DFL.DialogButton, { style: {
                    marginLeft: "0px",
                    height: "30px",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    padding: "5px 0px 0px 0px",
                    minWidth: "40px",
                }, onClick: () => onConfigChange(MULTIPLIER, Math.max(1, config.multiplier - 1)), disabled: config.multiplier <= 1 }, "\u2212"),
            window.SP_REACT.createElement("div", { style: {
                    marginLeft: "20px",
                    marginRight: "20px",
                    fontSize: "16px",
                    fontWeight: "bold",
                    color: config.multiplier > 4 ? "red" : "white",
                    minWidth: "60px",
                    textAlign: "center"
                } }, config.multiplier < 2 ? "OFF" : `${config.multiplier}X`),
            window.SP_REACT.createElement(DFL.DialogButton, { style: {
                    marginLeft: "0px",
                    height: "30px",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    padding: "5px 0px 0px 0px",
                    minWidth: "40px",
                }, onClick: () => onConfigChange(MULTIPLIER, Math.min(4, config.multiplier + 1)), disabled: config.multiplier >= 4 }, "+"))));
}

function NerdStuffModal({ closeModal }) {
    const [dllStats, setDllStats] = SP_REACT.useState(null);
    const [configContent, setConfigContent] = SP_REACT.useState(null);
    const [scriptContent, setScriptContent] = SP_REACT.useState(null);
    const [loading, setLoading] = SP_REACT.useState(true);
    const [error, setError] = SP_REACT.useState(null);
    SP_REACT.useEffect(() => {
        const loadData = async () => {
            try {
                setLoading(true);
                setError(null);
                // Load all data in parallel
                const [dllResult, configResult, scriptResult] = await Promise.all([
                    getDllStats(),
                    getConfigFileContent(),
                    getLaunchScriptContent()
                ]);
                setDllStats(dllResult);
                setConfigContent(configResult);
                setScriptContent(scriptResult);
            }
            catch (err) {
                setError(err instanceof Error ? err.message : "Failed to load data");
            }
            finally {
                setLoading(false);
            }
        };
        loadData();
    }, []);
    const formatSHA256 = (hash) => {
        // Format SHA256 hash for better readability (add spaces every 8 characters)
        return hash.replace(/(.{8})/g, '$1 ').trim();
    };
    const copyToClipboard = async (text) => {
        try {
            await navigator.clipboard.writeText(text);
            // Could add a toast notification here if desired
        }
        catch (err) {
            console.error("Failed to copy to clipboard:", err);
        }
    };
    return (window.SP_REACT.createElement(DFL.ModalRoot, { onCancel: closeModal, onOK: closeModal },
        loading && (window.SP_REACT.createElement("div", null, "Loading information...")),
        error && (window.SP_REACT.createElement("div", null,
            "Error: ",
            error)),
        !loading && !error && (window.SP_REACT.createElement(window.SP_REACT.Fragment, null,
            dllStats && (window.SP_REACT.createElement(window.SP_REACT.Fragment, null, !dllStats.success ? (window.SP_REACT.createElement("div", null, dllStats.error || "Failed to get DLL stats")) : (window.SP_REACT.createElement("div", null,
                window.SP_REACT.createElement(DFL.Field, { label: "DLL Path" },
                    window.SP_REACT.createElement(DFL.Focusable, { onClick: () => dllStats.dll_path && copyToClipboard(dllStats.dll_path), onActivate: () => dllStats.dll_path && copyToClipboard(dllStats.dll_path) }, dllStats.dll_path || "Not available")),
                window.SP_REACT.createElement(DFL.Field, { label: "DLL SHA256 Hash" },
                    window.SP_REACT.createElement(DFL.Focusable, { onClick: () => dllStats.dll_sha256 && copyToClipboard(dllStats.dll_sha256), onActivate: () => dllStats.dll_sha256 && copyToClipboard(dllStats.dll_sha256) }, dllStats.dll_sha256 ? formatSHA256(dllStats.dll_sha256) : "Not available")),
                dllStats.dll_source && (window.SP_REACT.createElement(DFL.Field, { label: "Detection Source" },
                    window.SP_REACT.createElement("div", null, dllStats.dll_source))))))),
            scriptContent && (window.SP_REACT.createElement(DFL.Field, { label: "Launch Script" }, !scriptContent.success ? (window.SP_REACT.createElement("div", null,
                "Script not found: ",
                scriptContent.error)) : (window.SP_REACT.createElement("div", null,
                window.SP_REACT.createElement("div", { style: { marginBottom: "8px", fontSize: "0.9em", opacity: 0.8 } },
                    "Path: ",
                    scriptContent.path),
                window.SP_REACT.createElement(DFL.Focusable, { onClick: () => scriptContent.content && copyToClipboard(scriptContent.content), onActivate: () => scriptContent.content && copyToClipboard(scriptContent.content) },
                    window.SP_REACT.createElement("pre", { style: {
                            background: "rgba(255, 255, 255, 0.1)",
                            padding: "8px",
                            borderRadius: "4px",
                            fontSize: "0.8em",
                            whiteSpace: "pre-wrap",
                            overflow: "auto",
                            maxHeight: "150px"
                        } }, scriptContent.content || "No content")))))),
            configContent && (window.SP_REACT.createElement(DFL.Field, { label: "Configuration File" }, !configContent.success ? (window.SP_REACT.createElement("div", null,
                "Config not found: ",
                configContent.error)) : (window.SP_REACT.createElement("div", null,
                window.SP_REACT.createElement("div", { style: { marginBottom: "8px", fontSize: "0.9em", opacity: 0.8 } },
                    "Path: ",
                    configContent.path),
                window.SP_REACT.createElement(DFL.Focusable, { onClick: () => configContent.content && copyToClipboard(configContent.content), onActivate: () => configContent.content && copyToClipboard(configContent.content) },
                    window.SP_REACT.createElement("pre", { style: {
                            background: "rgba(255, 255, 255, 0.1)",
                            padding: "8px",
                            borderRadius: "4px",
                            fontSize: "0.8em",
                            whiteSpace: "pre-wrap",
                            overflow: "auto"
                        } }, configContent.content || "No content")))))),
            window.SP_REACT.createElement(DFL.DialogControlsSection, null,
                window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                    window.SP_REACT.createElement(DFL.ButtonItem, { layout: "below", onClick: closeModal }, "Close")))))));
}

var flatpakTargetImage = 'http://127.0.0.1:1337/plugins/Decky LSFG-VK/assets/flatpak-target-34f0e3b7.png';

const FlatpaksModal = ({ closeModal }) => {
    const [extensionStatus, setExtensionStatus] = SP_REACT.useState(null);
    const [flatpakApps, setFlatpakApps] = SP_REACT.useState(null);
    const [loading, setLoading] = SP_REACT.useState(true);
    const [operationInProgress, setOperationInProgress] = SP_REACT.useState(null);
    const loadData = async () => {
        setLoading(true);
        try {
            const [statusResult, appsResult] = await Promise.all([
                checkFlatpakExtensionStatus(),
                getFlatpakApps()
            ]);
            setExtensionStatus(statusResult);
            setFlatpakApps(appsResult);
        }
        catch (error) {
            console.error('Error loading Flatpak data:', error);
        }
        finally {
            setLoading(false);
        }
    };
    SP_REACT.useEffect(() => {
        loadData();
    }, []);
    const handleExtensionOperation = async (operation, version) => {
        const operationId = `${operation}-${version}`;
        setOperationInProgress(operationId);
        try {
            const result = operation === 'install'
                ? await installFlatpakExtension(version)
                : await uninstallFlatpakExtension(version);
            if (result.success) {
                // Reload status after operation
                const newStatus = await checkFlatpakExtensionStatus();
                setExtensionStatus(newStatus);
            }
        }
        catch (error) {
            console.error(`Error ${operation}ing extension:`, error);
        }
        finally {
            setOperationInProgress(null);
        }
    };
    const handleAppOverrideToggle = async (app) => {
        const hasOverrides = app.has_filesystem_override && app.has_env_override;
        const operationId = `app-${app.app_id}`;
        setOperationInProgress(operationId);
        try {
            const result = hasOverrides
                ? await removeFlatpakAppOverride(app.app_id)
                : await setFlatpakAppOverride(app.app_id);
            if (result.success) {
                // Reload apps data after operation
                const newApps = await getFlatpakApps();
                setFlatpakApps(newApps);
            }
        }
        catch (error) {
            console.error('Error toggling app override:', error);
        }
        finally {
            setOperationInProgress(null);
        }
    };
    const confirmOperation = (operation, title, description) => {
        DFL.showModal(window.SP_REACT.createElement(DFL.ConfirmModal, { strTitle: title, strDescription: description, onOK: operation, onCancel: () => { } }));
    };
    if (loading) {
        return (window.SP_REACT.createElement(DFL.ModalRoot, { closeModal: closeModal },
            window.SP_REACT.createElement(DFL.DialogHeader, null, "Flatpak Extensions"),
            window.SP_REACT.createElement(DFL.DialogBody, null,
                window.SP_REACT.createElement("div", { style: { display: 'flex', justifyContent: 'center', padding: '20px' } },
                    window.SP_REACT.createElement(DFL.Spinner, null)))));
    }
    const instructionSteps = [
        {
            id: 'try-first',
            title: 'Try first:',
            command: '~/lsfg'
        },
        {
            id: 'try-full-path',
            title: "If that doesn't work, try full path:",
            command: '/home/(username)/lsfg'
        },
        {
            id: 'final-result',
            title: 'Final result should look like:',
            command: '~/lsfg "usr/bin/flatpak"'
        }
    ];
    const focusableInstructionStyle = {
        padding: '10px',
        background: 'rgba(0, 0, 0, 0.3)',
        borderRadius: '6px',
        marginBottom: '12px'
    };
    const commandStyle = {
        fontFamily: 'monospace',
        fontSize: '0.85em',
        background: 'rgba(0, 0, 0, 0.45)',
        padding: '8px',
        borderRadius: '4px',
        marginTop: '6px'
    };
    return (window.SP_REACT.createElement(DFL.ModalRoot, { closeModal: closeModal },
        window.SP_REACT.createElement(DFL.DialogHeader, null, "Flatpak Extensions"),
        window.SP_REACT.createElement(DFL.DialogBody, null,
            window.SP_REACT.createElement(DFL.Focusable, null,
                window.SP_REACT.createElement(DFL.DialogControlsSection, null,
                    window.SP_REACT.createElement(DFL.DialogControlsSectionHeader, null, "Runtime Extension Installer"),
                    extensionStatus && extensionStatus.success ? (window.SP_REACT.createElement(window.SP_REACT.Fragment, null,
                        window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                            window.SP_REACT.createElement(DFL.Field, { label: "Runtime 23.08", description: extensionStatus.installed_23_08 ? "Installed" : "Not installed", icon: extensionStatus.installed_23_08 ? window.SP_REACT.createElement(FaCheck, { style: { color: 'green' } }) : window.SP_REACT.createElement(FaTimes, { style: { color: 'red' } }) },
                                window.SP_REACT.createElement(DFL.ButtonItem, { layout: "below", onClick: () => {
                                        const operation = extensionStatus.installed_23_08 ? 'uninstall' : 'install';
                                        const action = () => handleExtensionOperation(operation, '23.08');
                                        if (operation === 'uninstall') {
                                            confirmOperation(action, 'Uninstall Runtime Extension', 'Are you sure you want to uninstall the 23.08 runtime extension?');
                                        }
                                        else {
                                            action();
                                        }
                                    }, disabled: operationInProgress === 'install-23.08' || operationInProgress === 'uninstall-23.08' }, operationInProgress === 'install-23.08' || operationInProgress === 'uninstall-23.08' ? (window.SP_REACT.createElement(DFL.Spinner, null)) : extensionStatus.installed_23_08 ? (window.SP_REACT.createElement(window.SP_REACT.Fragment, null,
                                    window.SP_REACT.createElement(FaTrash, null),
                                    " Uninstall")) : (window.SP_REACT.createElement(window.SP_REACT.Fragment, null,
                                    window.SP_REACT.createElement(FaDownload, null),
                                    " Install"))))),
                        window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                            window.SP_REACT.createElement(DFL.Field, { label: "Runtime 24.08", description: extensionStatus.installed_24_08 ? "Installed" : "Not installed", icon: extensionStatus.installed_24_08 ? window.SP_REACT.createElement(FaCheck, { style: { color: 'green' } }) : window.SP_REACT.createElement(FaTimes, { style: { color: 'red' } }) },
                                window.SP_REACT.createElement(DFL.ButtonItem, { layout: "below", onClick: () => {
                                        const operation = extensionStatus.installed_24_08 ? 'uninstall' : 'install';
                                        const action = () => handleExtensionOperation(operation, '24.08');
                                        if (operation === 'uninstall') {
                                            confirmOperation(action, 'Uninstall Runtime Extension', 'Are you sure you want to uninstall the 24.08 runtime extension?');
                                        }
                                        else {
                                            action();
                                        }
                                    }, disabled: operationInProgress === 'install-24.08' || operationInProgress === 'uninstall-24.08' }, operationInProgress === 'install-24.08' || operationInProgress === 'uninstall-24.08' ? (window.SP_REACT.createElement(DFL.Spinner, null)) : extensionStatus.installed_24_08 ? (window.SP_REACT.createElement(window.SP_REACT.Fragment, null,
                                    window.SP_REACT.createElement(FaTrash, null),
                                    " Uninstall")) : (window.SP_REACT.createElement(window.SP_REACT.Fragment, null,
                                    window.SP_REACT.createElement(FaDownload, null),
                                    " Install"))))),
                        window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                            window.SP_REACT.createElement(DFL.Field, { label: "Runtime 25.08", description: extensionStatus.installed_25_08 ? "Installed" : "Not installed", icon: extensionStatus.installed_25_08 ? window.SP_REACT.createElement(FaCheck, { style: { color: 'green' } }) : window.SP_REACT.createElement(FaTimes, { style: { color: 'red' } }) },
                                window.SP_REACT.createElement(DFL.ButtonItem, { layout: "below", onClick: () => {
                                        const operation = extensionStatus.installed_25_08 ? 'uninstall' : 'install';
                                        const action = () => handleExtensionOperation(operation, '25.08');
                                        if (operation === 'uninstall') {
                                            confirmOperation(action, 'Uninstall Runtime Extension', 'Are you sure you want to uninstall the 25.08 runtime extension?');
                                        }
                                        else {
                                            action();
                                        }
                                    }, disabled: operationInProgress === 'install-25.08' || operationInProgress === 'uninstall-25.08' }, operationInProgress === 'install-25.08' || operationInProgress === 'uninstall-25.08' ? (window.SP_REACT.createElement(DFL.Spinner, null)) : extensionStatus.installed_25_08 ? (window.SP_REACT.createElement(window.SP_REACT.Fragment, null,
                                    window.SP_REACT.createElement(FaTrash, null),
                                    " Uninstall")) : (window.SP_REACT.createElement(window.SP_REACT.Fragment, null,
                                    window.SP_REACT.createElement(FaDownload, null),
                                    " Install"))))))) : (window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                        window.SP_REACT.createElement(DFL.Field, { label: "Error", description: extensionStatus?.error || 'Failed to check extension status', icon: window.SP_REACT.createElement(FaTimes, { style: { color: 'red' } }) })))),
                window.SP_REACT.createElement(DFL.DialogControlsSection, null,
                    window.SP_REACT.createElement(DFL.DialogControlsSectionHeader, null, "Flatpak Applications"),
                    flatpakApps && flatpakApps.success ? (flatpakApps.apps.length > 0 ? (flatpakApps.apps.map((app) => {
                        const hasOverrides = app.has_filesystem_override && app.has_env_override;
                        const partialOverrides = app.has_filesystem_override || app.has_env_override;
                        let statusColor = 'red';
                        let statusText = 'No overrides';
                        if (hasOverrides) {
                            statusColor = 'green';
                            statusText = 'Configured';
                        }
                        else if (partialOverrides) {
                            statusColor = 'orange';
                            statusText = 'Partial';
                        }
                        return (window.SP_REACT.createElement(DFL.PanelSectionRow, { key: app.app_id },
                            window.SP_REACT.createElement(DFL.Field, { label: app.app_name || app.app_id, description: `${app.app_id} - ${statusText}`, icon: window.SP_REACT.createElement(FaCog, { style: { color: statusColor } }) },
                                window.SP_REACT.createElement(DFL.Toggle, { value: hasOverrides, onChange: () => handleAppOverrideToggle(app), disabled: operationInProgress === `app-${app.app_id}` }))));
                    })) : (window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                        window.SP_REACT.createElement(DFL.Field, { label: "No Flatpak Apps Found", description: "No Flatpak applications are currently installed" })))) : (window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                        window.SP_REACT.createElement(DFL.Field, { label: "Error", description: flatpakApps?.error || 'Failed to load Flatpak applications', icon: window.SP_REACT.createElement(FaTimes, { style: { color: 'red' } }) })))),
                window.SP_REACT.createElement(DFL.DialogControlsSection, null,
                    window.SP_REACT.createElement(DFL.DialogControlsSectionHeader, null, "Steam Configuration"),
                    window.SP_REACT.createElement("div", { style: {
                            padding: '12px',
                            background: 'rgba(255, 255, 255, 0.1)',
                            borderRadius: '8px',
                            margin: '8px 0',
                            display: 'flex',
                            flexDirection: 'column'
                        } },
                        window.SP_REACT.createElement("div", { style: { fontWeight: 'bold', marginBottom: '8px', color: '#fff' } }, "Configure Steam Flatpak Shortcuts"),
                        window.SP_REACT.createElement("div", { style: { fontSize: '0.9em', lineHeight: '1.4', marginBottom: '8px' } }, "In Steam, open your flatpak game and click the cog wheel."),
                        window.SP_REACT.createElement("div", { style: { fontSize: '0.9em', lineHeight: '1.4', marginBottom: '12px', color: '#ffa500' } },
                            window.SP_REACT.createElement("strong", null, "IMPORTANT:"),
                            " Set this in TARGET (NOT LAUNCH OPTIONS)"),
                        instructionSteps.map((step) => (window.SP_REACT.createElement(DFL.Focusable, { key: step.id, focusWithinClassName: "gpfocuswithin", onActivate: () => { }, style: focusableInstructionStyle },
                            window.SP_REACT.createElement("div", { style: { fontWeight: 'bold' } }, step.title),
                            window.SP_REACT.createElement("div", { style: commandStyle }, step.command)))),
                        window.SP_REACT.createElement(DFL.Focusable, { focusWithinClassName: "gpfocuswithin", onActivate: () => { }, style: { marginTop: '4px' } },
                            window.SP_REACT.createElement("div", { style: { textAlign: 'center' } },
                                window.SP_REACT.createElement("img", { src: flatpakTargetImage.replace(/ /g, '%20'), alt: "Steam Properties Target Field Example", style: {
                                        maxWidth: '100%',
                                        height: 'auto',
                                        border: '1px solid rgba(255, 255, 255, 0.2)',
                                        borderRadius: '4px'
                                    } }))))),
                window.SP_REACT.createElement(DFL.DialogControlsSection, null,
                    window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                        window.SP_REACT.createElement(DFL.ButtonItem, { layout: "below", onClick: closeModal }, "Close")))))));
};

function Content() {
    const { isInstalled, installationStatus, setIsInstalled, setInstallationStatus } = useInstallationStatus();
    const { dllDetected, dllDetectionStatus } = useDllDetection();
    const { config, loadLsfgConfig, updateField } = useLsfgConfig();
    const { currentProfile, updateProfileConfig, loadProfiles } = useProfileManagement();
    const { isInstalling, isUninstalling, handleInstall, handleUninstall } = useInstallationActions();
    SP_REACT.useEffect(() => {
        if (isInstalled) {
            loadLsfgConfig();
        }
    }, [isInstalled, loadLsfgConfig]);
    const handleConfigChange = async (fieldName, value) => {
        if (currentProfile) {
            const newConfig = { ...config, [fieldName]: value };
            const result = await updateProfileConfig(currentProfile, newConfig);
            if (result.success) {
                await loadLsfgConfig();
            }
        }
        else {
            await updateField(fieldName, value);
        }
    };
    const onInstall = () => {
        handleInstall(setIsInstalled, setInstallationStatus, loadLsfgConfig);
    };
    const onUninstall = () => {
        handleUninstall(setIsInstalled, setInstallationStatus);
    };
    const handleShowNerdStuff = () => {
        DFL.showModal(window.SP_REACT.createElement(NerdStuffModal, null));
    };
    const handleShowFlatpaks = () => {
        DFL.showModal(window.SP_REACT.createElement(FlatpaksModal, null));
    };
    return (window.SP_REACT.createElement(DFL.PanelSection, null,
        !isInstalled && (window.SP_REACT.createElement(window.SP_REACT.Fragment, null,
            window.SP_REACT.createElement(InstallationButton, { isInstalled: isInstalled, isInstalling: isInstalling, isUninstalling: isUninstalling, onInstall: onInstall, onUninstall: onUninstall }),
            window.SP_REACT.createElement(StatusDisplay, { dllDetected: dllDetected, dllDetectionStatus: dllDetectionStatus, isInstalled: isInstalled, installationStatus: installationStatus }))),
        isInstalled && (window.SP_REACT.createElement(window.SP_REACT.Fragment, null,
            window.SP_REACT.createElement(DFL.PanelSectionRow, null,
                window.SP_REACT.createElement("div", { style: {
                        fontSize: "14px",
                        fontWeight: "bold",
                        marginTop: "8px",
                        marginBottom: "6px",
                        borderBottom: "1px solid rgba(255, 255, 255, 0.2)",
                        paddingBottom: "3px",
                        color: "white"
                    } }, "FPS Multiplier")),
            window.SP_REACT.createElement(FpsMultiplierControl, { config: config, onConfigChange: handleConfigChange }))),
        isInstalled && (window.SP_REACT.createElement(ProfileManagement, { currentProfile: currentProfile, onProfileChange: async () => {
                await loadProfiles();
                await loadLsfgConfig();
            } })),
        isInstalled && (window.SP_REACT.createElement(ConfigurationSection, { config: config, onConfigChange: handleConfigChange })),
        isInstalled && (window.SP_REACT.createElement(window.SP_REACT.Fragment, null,
            window.SP_REACT.createElement(SmartClipboardButton, null),
            window.SP_REACT.createElement(FgmodClipboardButton, null))),
        window.SP_REACT.createElement(UsageInstructions, { config: config }),
        window.SP_REACT.createElement(DFL.PanelSectionRow, null,
            window.SP_REACT.createElement(DFL.ButtonItem, { layout: "below", onClick: handleShowNerdStuff }, "Nerd Stuff")),
        window.SP_REACT.createElement(DFL.PanelSectionRow, null,
            window.SP_REACT.createElement(DFL.ButtonItem, { layout: "below", onClick: handleShowFlatpaks }, "Flatpak Setup")),
        isInstalled && (window.SP_REACT.createElement(window.SP_REACT.Fragment, null,
            window.SP_REACT.createElement(StatusDisplay, { dllDetected: dllDetected, dllDetectionStatus: dllDetectionStatus, isInstalled: isInstalled, installationStatus: installationStatus }),
            window.SP_REACT.createElement(InstallationButton, { isInstalled: isInstalled, isInstalling: isInstalling, isUninstalling: isUninstalling, onInstall: onInstall, onUninstall: onUninstall })))));
}

var index = definePlugin(() => {
    console.log("decky-lsfg-vk plugin initializing");
    return {
        name: "Decky LSFG-VK",
        titleView: window.SP_REACT.createElement("div", { className: DFL.staticClasses.Title }, "Decky LSFG-VK"),
        alwaysRender: true,
        content: window.SP_REACT.createElement(Content, null),
        icon: window.SP_REACT.createElement(GiPlasticDuck, null),
        onDismount() {
            console.log("decky-lsfg-vk unloading");
        }
    };
});

export { index as default };
//# sourceMappingURL=index.js.map
