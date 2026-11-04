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

test('named library compares snapshots, safely exports CSV and supports rename and undo',async({page},testInfo)=>{
  await page.goto('/lab');await expect(page.locator('fieldset')).toBeEnabled();
  await expect(page.locator('[data-library-undo]')).not.toBeVisible();
  await page.locator('[data-save-name]').fill('<img src=x onerror=alert(1)>');await page.locator('[data-action=save]').click();
  await page.locator('.saved-experiment [data-entry-action=compare]').click();await expect(page.locator('[data-comparison-chart]')).not.toBeVisible();await expect(page.locator('[data-comparison-axis]')).toContainText('Run and save');
  await page.locator('[data-scenario=conflict]').click();for(let i=0;i<5;i++)await page.locator('[data-action=step]').click();await page.locator('[data-save-name]').fill('=Variant B');await page.locator('[data-action=save]').click();
  await expect(page.locator('.saved-experiment')).toHaveCount(2);await expect(page.locator('[data-library-list] img')).toHaveCount(0);
  await page.locator('.saved-experiment').nth(0).locator('[data-entry-action=compare]').click();
  await expect(page.locator('[data-comparison-chart]')).toBeVisible();
  await expect(page.locator('.saved-comparison-card')).toHaveCount(2);await expect(page.locator('[data-comparison-chart] polyline')).toHaveCount(2);
  const pending=page.waitForEvent('download');await page.locator('[data-entry-action=export_compare]').click();const download=await pending;
  const csv=await fs.readFile(await download.path(),'utf8');expect(csv).toContain('"\'=Variant B"');
  const first=page.locator('.saved-experiment').nth(0);await first.locator('[data-saved-name]').fill('Renamed variant');await first.getByRole('button',{name:'Rename',exact:true}).click();
  await expect(page.locator('.saved-experiment h3').first()).toHaveText('Renamed variant');
  await page.locator('.saved-experiment').first().getByRole('button',{name:'Remove',exact:true}).click();await expect(page.locator('.saved-experiment')).toHaveCount(1);
  await page.locator('[data-library-undo]').click();await expect(page.locator('.saved-experiment')).toHaveCount(2);
  await page.reload();await expect(page.locator('.saved-experiment')).toHaveCount(2);
  await page.locator('.saved-experiment').nth(0).locator('[data-entry-action=compare]').click();await page.locator('.saved-experiment').nth(1).locator('[data-entry-action=compare]').click();
  await page.locator('.lab-saved').screenshot({path:testInfo.outputPath('library-desktop.png')});
  await page.setViewportSize({width:360,height:900});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await page.locator('.lab-saved').screenshot({path:testInfo.outputPath('library-mobile.png')});
});

test('guided missions track real progress and shared links reproduce starting conditions',async({page,context})=>{
  const errors=[];page.on('pageerror',error=>errors.push(error.message));
  await page.goto('/lab');await expect(page.locator('fieldset')).toBeEnabled();
  await page.locator('[data-missions] summary').click();await expect(page.locator('.mission-card')).toHaveCount(3);
  await page.locator('[data-mission-start="common-ground"]').click();await expect(page.locator('[data-mission-title]')).toHaveText('Build common ground');
  await expect(page.locator('[data-mission-result]')).toHaveText('Mission in progress');
  for(let i=0;i<60;i++)await page.locator('[data-action=step]').click();
  await expect(page.locator('[data-mission-result]')).toContainText('All targets met');
  await page.locator('[data-share-conditions]').click();await expect(page.locator('[data-share-result]')).toBeVisible();
  const url=await page.locator('[data-share-link]').inputValue();expect(url).toContain('mission=common-ground');
  const second=await context.newPage();await second.goto(url);await expect(second.locator('fieldset')).toBeEnabled();
  await expect(second.locator('[data-stat=tick]')).toHaveText('0');await expect(second.locator('input[name=seed]')).toHaveValue('common-ground-v1');
  await expect(second.locator('[data-mission-badge=common-ground]')).toContainText('Completed locally');
  await second.locator('[data-mission-stop]').click();await expect(second.locator('[data-active-mission]')).not.toBeVisible();
  await second.setViewportSize({width:360,height:900});expect(await second.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await second.close();expect(errors).toEqual([]);
});


test('library archives transfer to another browser and invalid imports preserve saved worlds',async({page,browser})=>{
  await page.goto('/lab');await expect(page.locator('fieldset')).toBeEnabled();await page.locator('[data-save-name]').fill('Portable collection');await page.locator('[data-action=save]').click();
  const pending=page.waitForEvent('download');await page.locator('[data-entry-action=export_library]').click();const archive=await pending;const buffer=await fs.readFile(await archive.path());
  const other=await browser.newContext();const target=await other.newPage();await target.goto('http://127.0.0.1:4003/lab');await expect(target.locator('fieldset')).toBeEnabled();
  const upload=()=>target.locator('[data-import-library]').setInputFiles({name:'collection.json',mimeType:'application/json',buffer});
  await upload();await expect(target.locator('.saved-experiment h3')).toHaveText('Portable collection');
  await upload();await expect(target.locator('.saved-experiment')).toHaveCount(1);await expect(target.locator('[data-lab-notice]')).toContainText('skipped 1');
  await target.locator('[data-import-library]').setInputFiles({name:'broken.json',mimeType:'application/json',buffer:Buffer.from('broken')});await expect(target.locator('[data-lab-notice]')).toContainText('not a valid');await expect(target.locator('.saved-experiment')).toHaveCount(1);
  await target.setViewportSize({width:360,height:900});expect(await target.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await other.close();
});

test('corrupt local libraries offer exact recovery download and explicit reset',async({page})=>{
  await page.addInitScript(()=>{localStorage.setItem('evolving-minds:lab-library:v2','corrupt original');localStorage.setItem('unrelated-preference','keep')});
  await page.goto('/lab');await expect(page.locator('fieldset')).toBeEnabled();await expect(page.locator('[data-library-problem]')).toBeVisible();await page.locator('[data-action=step]').click();
  const pending=page.waitForEvent('download');await page.locator('[data-entry-action=backup_raw]').click();const original=await pending;expect(await fs.readFile(await original.path(),'utf8')).toBe('corrupt original');
  page.once('dialog',dialog=>dialog.dismiss());await page.locator('[data-entry-action=reset_library]').click();await expect(page.locator('[data-library-problem]')).toBeVisible();
  page.once('dialog',dialog=>dialog.accept());await page.locator('[data-entry-action=reset_library]').click();await expect(page.locator('[data-library-problem]')).not.toBeVisible();await expect(page.locator('[data-stat=tick]')).toHaveText('1');expect(await page.evaluate(()=>localStorage.getItem('unrelated-preference'))).toBe('keep');
  await page.locator('[data-action=save]').click();await expect(page.locator('.saved-experiment')).toHaveCount(1);
});

test('working sessions recover after reload and shared links start a new reproducible run',async({page})=>{
  await page.goto('/lab');await expect(page.locator('fieldset')).toBeEnabled();await page.locator('[data-missions] summary').click();await page.locator('[data-mission-start=common-ground]').click();
  await page.locator('[data-action=step]').click();await page.locator('[data-save-name]').fill('Session survivor');
  await page.locator('input[name=speed]').evaluate(el=>{el.value='4';el.dispatchEvent(new Event('input',{bubbles:true}))});
  await page.reload();await expect(page.locator('fieldset')).toBeEnabled();await expect(page.locator('[data-stat=tick]')).toHaveText('1');await expect(page.locator('[data-save-name]')).toHaveValue('Session survivor');await expect(page.locator('input[name=speed]')).toHaveValue('4');
  await expect(page.locator('[data-mission-title]')).toHaveText('Build common ground');await expect(page.locator('[data-action=play]')).toHaveAttribute('aria-pressed','false');await expect(page.locator('.saved-experiment')).toHaveCount(0);
  await page.goto('/lab?experiment=1&seed=shared-new&population=24&aggression=0.5&curiosity=0.5&mutation=0.12&epoch=normal');await expect(page.locator('fieldset')).toBeEnabled();await expect(page.locator('[data-stat=tick]')).toHaveText('0');await expect(page.locator('input[name=seed]')).toHaveValue('shared-new');
  await page.locator('[data-action=step]').click();await expect.poll(()=>new URL(page.url()).searchParams.has('experiment')).toBe(false);await page.reload();await expect(page.locator('fieldset')).toBeEnabled();await expect(page.locator('[data-stat=tick]')).toHaveText('1');await expect(page.locator('input[name=seed]')).toHaveValue('shared-new');
});

test('blocked session storage leaves the private simulator usable',async({page})=>{
  await page.addInitScript(()=>Object.defineProperty(window,'sessionStorage',{get(){throw new DOMException('Blocked','SecurityError')}}));
  await page.goto('/lab');await expect(page.locator('fieldset')).toBeEnabled();await expect(page.locator('[data-session-status]')).toContainText('unavailable');await page.locator('[data-action=step]').click();await expect(page.locator('[data-stat=tick]')).toHaveText('1');await page.locator('[data-action=save]').click();await expect(page.locator('.saved-experiment')).toHaveCount(1)
});
