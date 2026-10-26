/** opencode 可用模型 */
export class ModelInfo {
  /** 模型 id */
  id: string = '';
  providerID: string = '';
  variant: string = '';
  /** 展示名 */
  name: string = '';
  description: string = '';
  /** 每百万 token 价格（美元） */
  costInput: number = 0;
  costOutput: number = 0;
  /** 上下文长度 */
  context: number = 0;

  displayName(): string {
    if (this.name.length > 0) {
      return this.name;
    }
    if (this.id.length > 0) {
      return this.id;
    }
    return this.providerID;
  }

  /** 上下文展示，如 200K */
  contextLabel(): string {
    if (this.context <= 0) {
      return '';
    }
    if (this.context >= 1000000) {
      return (this.context / 1000000).toFixed(1) + 'M';
    }
    return Math.round(this.context / 1000) + 'K';
  }

  /** 价格倍率展示（相对最低价模型），无价格时为空 */
  ratioLabel(baseCost: number): string {
    if (baseCost <= 0 || this.costInput <= 0) {
      return '';
    }
    const r: number = this.costInput / baseCost;
    return r.toFixed(2) + 'x';
  }
}
