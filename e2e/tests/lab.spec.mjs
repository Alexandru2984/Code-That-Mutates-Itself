import {test,expect} from '@playwright/test'
import fs from 'node:fs/promises'

test('seeded experiments export reproducibly, save, reload and resume safely',async({page})=>{
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto('/lab');await expect(page.locator('fieldset')).toBeEnabled();
  await page.locator('[data-scenario=cooperation]').click();await page.locator('input[name=seed]').fill('browser-regression');
  const reset=()=>page.getByRole('button',{name:'Build / reset experiment',exact:false}).click();
  const exportWorld=async()=>{const pending=page.waitForEvent('download');await page.locator('[data-action=export]').click();const result=await pending;return JSON.parse(await fs.readFile(await result.path(),'utf8'))};
  await reset();await page.locator('[data-action=step]').click();const first=await exportWorld();expect(first.tick).toBe(1);
  await reset();await page.locator('[data-action=step]').click();expect(await exportWorld()).toEqual(first);
  await page.locator('[data-action=play]').click();await expect.poll(async()=>Number(await page.locator('[data-stat=tick]').textContent())).toBeGreaterThanOrEqual(4);
  await page.locator('[data-action=play]').click();const tick=await page.locator('[data-stat=tick]').textContent();
  await page.locator('[data-action=save]').click();await expect(page.locator('[data-lab-notice]')).toContainText('saved in this browser');
  await page.reload();await expect(page.locator('fieldset')).toBeEnabled();await page.locator('[data-action=load]').click();await expect(page.locator('[data-stat=tick]')).toHaveText(tick);
  await page.locator('[data-import]').setInputFiles({name:'experiment.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(first))});
  await expect(page.locator('[data-stat=tick]')).toHaveText('1');await expect(page.locator('[data-lab-notice]')).toContainText('imported and paused');
  await page.locator('[data-import]').setInputFiles({name:'invalid.json',mimeType:'application/json',buffer:Buffer.from('{"version":1}')});
  await expect(page.locator('[data-lab-notice]')).toContainText('not a valid');await expect(page.locator('[data-stat=tick]')).toHaveText('1');
  await page.context().setOffline(true);await page.locator('[data-action=step]').click();await expect(page.locator('[data-stat=tick]')).toHaveText('2');await page.context().setOffline(false);
  expect(errors).toEqual([]);
});
