import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import { AppConfig, generateUUID } from '../model/AppConfig';

const PREFS_NAME = 'growth_diary_prefs';
const CONFIGS_KEY = 'app_configs';
const CURRENT_CONFIG_ID_KEY = 'current_config_id';

/**
 * 本地偏好设置存储服务
 * 对应 Flutter 版本的 LocalStorageService
 */
export class PreferencesService {
  private static instance: PreferencesService;
  private context: common.UIAbilityContext | null = null;

  static getInstance(): PreferencesService {
    if (!PreferencesService.instance) {
      PreferencesService.instance = new PreferencesService();
    }
    return PreferencesService.instance;
  }

  /** 初始化，需要传入 Ability 上下文 */
  initialize(context: common.UIAbilityContext): void {
    this.context = context;
  }

  private async getPrefs(): Promise<preferences.Preferences> {
    if (!this.context) {
      throw new Error('PreferencesService not initialized');
    }
    return preferences.getPreferences(this.context, PREFS_NAME);
  }

  /** 保存单个配置 */
  async saveConfig(config: AppConfig): Promise<void> {
    const allConfigs = await this.loadAllConfigs();
    allConfigs[config.id] = config;
    await this.saveAllConfigs(allConfigs);
  }

  /** 保存所有配置 */
  async saveAllConfigs(configs: Record<string, AppConfig>): Promise<void> {
    const prefs = await this.getPrefs();
    const jsonStr = JSON.stringify(
      Object.fromEntries(
        Object.entries(configs).map(([k, v]) => [k, v.toJson()])
      )
    );
    await prefs.put(CONFIGS_KEY, jsonStr);
    await prefs.flush();
  }

  /** 加载所有配置 */
  async loadAllConfigs(): Promise<Record<string, AppConfig>> {
    try {
      const prefs = await this.getPrefs();
      const jsonStr = await prefs.get(CONFIGS_KEY, '') as string;
      if (jsonStr && jsonStr.length > 0) {
        const raw = JSON.parse(jsonStr) as Record<string, Record<string, Object>>;
        const result: Record<string, AppConfig> = {};
        for (const key of Object.keys(raw)) {
          result[key] = AppConfig.fromJson(raw[key]);
        }
        return result;
      }
    } catch (e) {
      console.error('PreferencesService loadAllConfigs error:', e);
    }
    return {};
  }

  /** 加载指定或当前配置 */
  async loadConfig(configId?: string): Promise<AppConfig | null> {
    const configs = await this.loadAllConfigs();
    if (configId) {
      return configs[configId] ?? null;
    }
    const currentId = await this.getCurrentConfigId();
    return currentId ? (configs[currentId] ?? null) : null;
  }

  /** 设置当前使用的配置 ID */
  async setCurrentConfigId(configId: string): Promise<void> {
    const prefs = await this.getPrefs();
    await prefs.put(CURRENT_CONFIG_ID_KEY, configId);
    await prefs.flush();
  }

  /** 获取当前使用的配置 ID */
  async getCurrentConfigId(): Promise<string> {
    try {
      const prefs = await this.getPrefs();
      return await prefs.get(CURRENT_CONFIG_ID_KEY, '') as string;
    } catch (e) {
      return '';
    }
  }

  /** 删除指定配置 */
  async deleteConfig(configId: string): Promise<void> {
    const configs = await this.loadAllConfigs();
    delete configs[configId];
    await this.saveAllConfigs(configs);

    // 如果删除的是当前配置，自动切换到第一个可用配置
    const currentId = await this.getCurrentConfigId();
    if (currentId === configId) {
      const remaining = Object.keys(configs);
      if (remaining.length > 0) {
        await this.setCurrentConfigId(remaining[0]);
      }
    }
  }

  /** 获取字符串值 */
  async getString(key: string): Promise<string> {
    try {
      const prefs = await this.getPrefs();
      return await prefs.get(key, '') as string;
    } catch (e) {
      return '';
    }
  }

  /** 保存字符串值 */
  async saveString(key: string, value: string): Promise<void> {
    const prefs = await this.getPrefs();
    await prefs.put(key, value);
    await prefs.flush();
  }

  /** 删除某个键 */
  async remove(key: string): Promise<void> {
    const prefs = await this.getPrefs();
    await prefs.delete(key);
    await prefs.flush();
  }
}
