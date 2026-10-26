export class SessionInfo {
  id: string = '';
  title: string = '';
  projectID: string = '';
  agent: string = '';
  /** 工程目录（opencode 的 location.directory） */
  location: string = '';
  timeCreated: number = 0;
  timeUpdated: number = 0;
  running: boolean = false;
}
