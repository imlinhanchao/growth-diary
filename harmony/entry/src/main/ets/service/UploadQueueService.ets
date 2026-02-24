import { PreferencesService } from './PreferencesService';

const QUEUE_KEY_PREFIX = 'upload_queue_';

/** 单个上传任务 */
export interface UploadTask {
  id: string;
  /** 所属配置（宝宝）ID */
  configId: string;
  /** 所属日记条目 ID */
  entryId: string;
  /** 本地文件 URI */
  localUri: string;
  /** 媒体类型 */
  type: 'photo' | 'video';
  /** 目标 WebDAV 相对路径，例如 media/xxx.jpg */
  targetPath: string;
  /** 任务状态 */
  status: 'pending' | 'uploading' | 'done' | 'failed';
  /** 失败原因 */
  errorMessage: string;
  /** 创建时间 ISO 字符串 */
  createdAt: string;
}

/**
 * 后台上传队列服务
 *
 * 将需要上传的媒体文件信息持久化到本地偏好存储，
 * 支持断点续传（重启应用后恢复队列继续上传）。
 * 实际的上传由调用者驱动（在 DiaryEditor 保存或后台恢复时触发）。
 */
export class UploadQueueService {
  private static instance: UploadQueueService;
  private prefsService = PreferencesService.getInstance();

  static getInstance(): UploadQueueService {
    if (!UploadQueueService.instance) {
      UploadQueueService.instance = new UploadQueueService();
    }
    return UploadQueueService.instance;
  }

  private queueKey(configId: string): string {
    return `${QUEUE_KEY_PREFIX}${configId}`;
  }

  /** 加载指定宝宝的所有上传任务 */
  async loadTasks(configId: string): Promise<UploadTask[]> {
    try {
      const json = await this.prefsService.getString(this.queueKey(configId));
      if (!json) return [];
      return JSON.parse(json) as UploadTask[];
    } catch {
      return [];
    }
  }

  /** 加载所有宝宝的待处理任务 */
  async loadPendingTasks(configId: string): Promise<UploadTask[]> {
    const tasks = await this.loadTasks(configId);
    return tasks.filter(t => t.status === 'pending' || t.status === 'failed');
  }

  /** 加载所有宝宝的上传中/待处理任务数量 */
  async getPendingCount(configId: string): Promise<number> {
    const tasks = await this.loadPendingTasks(configId);
    return tasks.length;
  }

  /** 添加任务到队列 */
  async enqueue(task: UploadTask): Promise<void> {
    const tasks = await this.loadTasks(task.configId);
    tasks.push(task);
    await this.saveTasks(task.configId, tasks);
  }

  /** 批量添加任务 */
  async enqueueBatch(tasks: UploadTask[]): Promise<void> {
    if (tasks.length === 0) return;
    const configId = tasks[0].configId;
    const existing = await this.loadTasks(configId);
    existing.push(...tasks);
    await this.saveTasks(configId, existing);
  }

  /** 更新任务状态 */
  async updateTaskStatus(
    configId: string,
    taskId: string,
    status: UploadTask['status'],
    errorMessage: string = '',
  ): Promise<void> {
    const tasks = await this.loadTasks(configId);
    const idx = tasks.findIndex(t => t.id === taskId);
    if (idx >= 0) {
      tasks[idx].status = status;
      tasks[idx].errorMessage = errorMessage;
      await this.saveTasks(configId, tasks);
    }
  }

  /** 删除已完成任务（清理） */
  async clearDoneTasks(configId: string): Promise<void> {
    const tasks = await this.loadTasks(configId);
    const remaining = tasks.filter(t => t.status !== 'done');
    await this.saveTasks(configId, remaining);
  }

  /** 清除某条目的所有任务 */
  async clearEntryTasks(configId: string, entryId: string): Promise<void> {
    const tasks = await this.loadTasks(configId);
    const remaining = tasks.filter(t => t.entryId !== entryId);
    await this.saveTasks(configId, remaining);
  }

  /** 获取正在进行中或待上传的任务数量（用于 UI 显示） */
  async getActiveCount(configId: string): Promise<number> {
    const tasks = await this.loadTasks(configId);
    return tasks.filter(t => t.status === 'pending' || t.status === 'uploading').length;
  }

  private async saveTasks(configId: string, tasks: UploadTask[]): Promise<void> {
    await this.prefsService.saveString(this.queueKey(configId), JSON.stringify(tasks));
  }
}
