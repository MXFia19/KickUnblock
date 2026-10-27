// KickUnblock — Worker (Cloudflare) : relaie l'API de Kick (liste fermée de
// chemins) et ses flux vidéo HLS (playlists réécrites pour passer par ici,
// segments), comme le Worker de TwitchUnblock le fait pour Twitch.
//
// Requêtes honnêtes : le Worker transmet le navigateur (User-Agent) et la
// langue du visiteur, rien d'autre — pas d'imitation d'un navigateur, ni
// d'Origin ou de Referer de kick.com. Si Kick refuse le Worker, on s'arrête là.
//
//   GET /test                   → Kick accepte-t-il ce Worker ? (API, flux)
//   GET /kick/<chemin>?<query>  → JSON de kick.com (chemins autorisés plus bas)
//   GET /hls?u=<adresse>        → playlist réécrite, ou segment (hôtes vidéo de Kick)

const KICK = 'https://kick.com'

// Chemins de l'API de Kick relayés : rien d'autre.
const API_PATHS = [
  /^\/api\/v2\/channels\/[A-Za-z0-9_-]{1,40}$/,
  /^\/api\/v2\/channels\/[A-Za-z0-9_-]{1,40}\/(livestream|videos|clips)$/,
  /^\/api\/v2\/channels\/\d{1,12}\/messages$/,
  /^\/api\/v1\/video\/[0-9a-f-]{36}$/,
  /^\/api\/v2\/clips\/[A-Za-z0-9_-]{1,64}$/,
  /^\/api\/search$/,
  /^\/api\/v1\/subcategories(\/[a-z0-9-]{1,80})?$/,
  /^\/stream\/livestreams\/[a-z]{2}$/,
]

// Hôtes des flux vidéo de Kick : Amazon IVS (directs), VODs, clips.
const VIDEO_HOST = /(^|\.)(live-video\.net|stream\.kick\.com|clips\.kick\.com)$/

const MAX_PLAYLIST = 2_000_000

function cors(headers = {}) {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Expose-Headers': 'Content-Length, Content-Range, Accept-Ranges',
    ...headers,
  }
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: cors({ 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' }),
  })
}

/** En-têtes transmis à Kick : ceux du visiteur, rien d'inventé. */
function forwardHeaders(req, accept) {
  const h = { Accept: accept }
  const ua = req.headers.get('User-Agent')
  const lang = req.headers.get('Accept-Language')
  if (ua) h['User-Agent'] = ua
  if (lang) h['Accept-Language'] = lang
  return h
}

async function api(req, url) {
  const path = url.pathname.slice('/kick'.length)
  if (!API_PATHS.some((re) => re.test(path)) || url.search.length > 500) return json({ error: 'path' }, 404)
  const r = await fetch(KICK + path + url.search, {
    headers: forwardHeaders(req, 'application/json'),
    // Lectures publiques : gardées un peu par Cloudflare (moins de requêtes chez Kick).
    cf: { cacheTtl: 15, cacheEverything: true },
  })
  return new Response(r.body, {
    status: r.status,
    headers: cors({ 'Content-Type': r.headers.get('content-type') || 'application/json', 'Cache-Control': 'public, max-age=15' }),
  })
}

/** Toute adresse de la playlist (lignes et attributs URI) repasse par /hls. */
function rewritePlaylist(text, base, self) {
  const wrap = (u) => `${self}/hls?u=${encodeURIComponent(new URL(u, base).href)}`
  return text.split('\n').map((line) => {
    const l = line.trim()
    if (!l) return line
    if (!l.startsWith('#')) return wrap(l)
    return line.replace(/URI="([^"]+)"/g, (_, u) => `URI="${wrap(u)}"`)
  }).join('\n')
}

async function hls(req, url) {
  let target
  try {
    target = new URL(url.searchParams.get('u') || '')
  } catch {
    return json({ error: 'bad_url' }, 400)
  }
  if (target.protocol !== 'https:' || !VIDEO_HOST.test(target.hostname)) return json({ error: 'host' }, 403)
  const headers = forwardHeaders(req, '*/*')
  const range = req.headers.get('Range')
  if (range) headers.Range = range
  const r = await fetch(target.href, { headers })
  const type = r.headers.get('content-type') || ''
  if (/mpegurl/i.test(type) || target.pathname.endsWith('.m3u8')) {
    const text = await r.text()
    if (text.length > MAX_PLAYLIST) return json({ error: 'too_big' }, 502)
    const body = r.ok ? rewritePlaylist(text, target.href, url.origin) : text
    return new Response(body, {
      status: r.status,
      headers: cors({ 'Content-Type': 'application/vnd.apple.mpegurl', 'Cache-Control': 'no-store' }),
    })
  }
  const out = cors({ 'Content-Type': type || 'application/octet-stream', 'Cache-Control': r.headers.get('cache-control') || 'public, max-age=60' })
  for (const k of ['content-length', 'content-range', 'accept-ranges']) {
    const v = r.headers.get(k)
    if (v) out[k] = v
  }
  return new Response(r.body, { status: r.status, headers: out })
}

/** Diagnostic : lives, chaîne, flux d'un direct (playlist, variante, segment). */
async function test(req) {
  const out = { worker: 'ok' }
  const step = async (label, u, accept) => {
    try {
      const r = await fetch(u, { headers: forwardHeaders(req, accept) })
      out[label] = r.status
      return r
    } catch (e) {
      out[label] = 'erreur : ' + e.message
      return null
    }
  }
  const lives = await step('api_lives', `${KICK}/stream/livestreams/en?page=1&limit=3&sort=desc`, 'application/json')
  const data = lives?.ok ? await lives.json().catch(() => null) : null
  if (lives && !lives.ok) out.api_lives_reponse = (await lives.text().catch(() => '')).slice(0, 200)
  const slug = data?.data?.[0]?.channel?.slug
  out.chaine = slug || null
  if (slug) {
    const ch = await step('api_chaine', `${KICK}/api/v2/channels/${slug}`, 'application/json')
    const c = ch?.ok ? await ch.json().catch(() => null) : null
    if (c?.playback_url) {
      const m = await step('flux_playlist', c.playback_url, '*/*')
      const txt = m?.ok ? await m.text() : ''
      const variant = txt.split('\n').find((l) => l && !l.startsWith('#'))
      if (variant) {
        const vu = new URL(variant, c.playback_url)
        const v = await step('flux_variante', vu.href, '*/*')
        const vt = v?.ok ? await v.text() : ''
        const seg = vt.split('\n').find((l) => l && !l.startsWith('#'))
        if (seg) {
          const s = await step('flux_segment', new URL(seg, vu).href, '*/*')
          await s?.body?.cancel()
        }
      }
    }
  }
  const ok = out.api_lives === 200 && out.api_chaine === 200 && out.flux_playlist === 200 && out.flux_segment === 200
  out.verdict = ok ? 'OK : Kick accepte ce Worker' : 'Refusé ou incomplet : Kick n\'accepte pas (tout) ce Worker'
  return json(out)
}

export default {
  async fetch(req) {
    const url = new URL(req.url)
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors({ 'Access-Control-Allow-Methods': 'GET', 'Access-Control-Allow-Headers': 'Range' }) })
    if (req.method !== 'GET') return json({ error: 'method' }, 405)
    try {
      if (url.pathname === '/test') return await test(req)
      if (url.pathname.startsWith('/kick/')) return await api(req, url)
      if (url.pathname === '/hls') return await hls(req, url)
      return json({ service: 'KickUnblock', routes: ['/test', '/kick/<chemin>', '/hls?u='] })
    } catch (e) {
      return json({ error: 'internal', message: String(e && e.message || e).slice(0, 200) }, 502)
    }
  },
}
