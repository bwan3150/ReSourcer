import client from './client'

export function getPlaylist(uuid, folderPath, mode, { sort, fileType, currentQueue } = {}) {
  return client.get('/api/playlist', {
    params: {
      uuid,
      folder_path: folderPath,
      mode,
      sort,
      file_type: fileType,
      current_queue: currentQueue?.join(','),
    },
  })
}
