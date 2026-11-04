import {test,expect} from '@playwright/test'

test.use({httpCredentials:{username:'admin',password:'secret',origin:'http://127.0.0.1:4003'}})

const cachePaths=page=>page.evaluate(async()=>{
  const paths=[]
  for(const name of await caches.keys())if(name.startsWith('evolving-minds-offline-'))for(const request of await(await caches.open(name)).keys())paths.push(new URL(request.url).pathname)
  return paths
})

test('standalone lab runs without a LiveView session or socket',async({page})=>{
  const errors=[],sockets=[];page.on('pageerror',error=>errors.push(error.message));page.on('websocket',socket=>sockets.push(socket.url()));
  const response=await page.goto('/offline');await expect(page.locator('fieldset')).toBeEnabled();
  expect(response.headers()['x-offline-shell']).toBe('1');expect(await page.locator('meta[name=csrf-token]').count()).toBe(0)
  await page.locator('[data-action=step]').click();await expect(page.locator('[data-stat=tick]')).toHaveText('1');
  await page.locator('[data-action=save]').click();await expect(page.locator('.saved-experiment')).toHaveCount(1);
  expect(sockets).toEqual([]);expect(errors).toEqual([])
  await page.getByRole('link',{name:'Observatory',exact:true}).click();await expect(page.locator('.phx-connected')).toBeVisible();sockets.length=0;
  await page.getByRole('link',{name:'Lab',exact:true}).click();await expect(page.locator('fieldset')).toBeEnabled();expect(sockets).toEqual([])
})

test('prepared lab reloads offline while private pages and live data remain uncached',async({page,context})=>{
  test.setTimeout(60_000)
  const errors=[];page.on('pageerror',error=>errors.push(error.message))
  await page.goto('/lab');await expect(page.locator('fieldset')).toBeEnabled();await page.locator('[data-action=step]').click();await expect(page.locator('[data-stat=tick]')).toHaveText('1');await page.locator('[data-save-name]').fill('Offline survivor');await page.locator('[data-action=save]').click()
  expect(await page.evaluate(()=>JSON.parse(localStorage.getItem('evolving-minds:lab-library:v2')).entries[0].world.tick)).toBe(1);
  await page.locator('[data-enable-offline]').click();await expect(page.locator('[data-pwa-mode]')).toHaveText('Offline ready',{timeout:40_000})
  await expect.poll(()=>page.evaluate(()=>!!navigator.serviceWorker.controller)).toBe(true)
  const paths=await cachePaths(page);expect(paths).toContain('/offline');expect(paths).toContain('/manifest.webmanifest');expect(paths).toHaveLength(7)
  expect(paths.some(path=>['/','/lab','/tree'].includes(path)||/^\/(admin|api|live|healthz)/.test(path))).toBe(false)
  const cachedShell=await page.evaluate(async()=>{for(const name of await caches.keys())if(name.startsWith('evolving-minds-offline-'))return(await(await caches.open(name)).match('/offline')).text()})
  expect(cachedShell).not.toContain('data-phx-session');expect(cachedShell).not.toContain('csrf-token')
  expect(await page.evaluate(async()=>[(await fetch('/admin/world')).status,(await fetch('/api/world')).status])).toEqual([200,200]);expect(await cachePaths(page)).toEqual(paths)
  await context.setOffline(true);await page.goto('/lab');await expect(page.locator('fieldset')).toBeEnabled();await expect(page.locator('[data-offline-state]')).toContainText('You are offline');await expect(page.locator('.saved-experiment h3')).toHaveText('Offline survivor')
  await page.locator('[data-action=load]').click();await expect(page.locator('[data-lab-notice]')).toContainText('loaded and paused');await expect(page.locator('[data-stat=tick]')).toHaveText('1');await page.locator('[data-action=step]').click();await expect(page.locator('[data-stat=tick]')).toHaveText('2')
  await page.reload();await expect(page.locator('fieldset')).toBeEnabled();await expect(page.locator('.saved-experiment')).toHaveCount(1)
  expect(await page.evaluate(async()=>{try{await fetch('/api/world');return 'networked'}catch(_){return 'offline'}})).toBe('offline')
  await page.setViewportSize({width:360,height:900});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);expect(errors).toEqual([])
  await context.setOffline(false);await page.locator('[data-remove-offline]').click();await expect(page.locator('[data-pwa-status]')).toContainText('Offline files removed');await expect(page.locator('.saved-experiment')).toHaveCount(1);expect(await cachePaths(page)).toEqual([])
})
