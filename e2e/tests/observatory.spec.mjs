import {test,expect} from '@playwright/test'

test('product pages fit mobile, tablet and desktop without horizontal scrolling',async({page})=>{
  for(const path of ['/','/tree','/lab']){
    await page.goto(path);await expect(page.locator('.phx-connected')).toBeVisible();
    for(const width of [360,390,768,1440,1920]){
      await page.setViewportSize({width,height:900});
      expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
    }
  }
});

test('watchlist survives reload and dossier links are shareable and keyboard accessible',async({page})=>{
  await page.goto('/');await expect(page.locator('.mind-card').first()).toBeVisible();
  const card=page.locator('.mind-card').first(),id=await card.getAttribute('id');
  await card.locator('.star-button').click();await expect(card.locator('.star-button')).toHaveAttribute('aria-pressed','true');
  await page.reload();await expect(page.locator(`#${id} .star-button`)).toHaveAttribute('aria-pressed','true');
  await page.locator(`#${id}`).getByRole('button',{name:'Details',exact:false}).click();await expect(page).toHaveURL(/mind=/);
  await expect(page.locator('#entity-detail')).toBeVisible();await page.keyboard.press('Escape');await expect(page.locator('#entity-detail')).toHaveCount(0);
  await page.getByRole('button',{name:'Field guide',exact:false}).click();await expect(page.locator('#field-guide-dialog')).toBeVisible();
  await page.keyboard.press('Tab');expect(await page.evaluate(()=>!!document.activeElement.closest('[role=dialog]'))).toBe(true);
  await page.keyboard.press('Escape');await expect(page.locator('#field-guide-dialog')).toHaveCount(0);
});

test('a live energy update moves cards to their correct sorted DOM positions',async({page})=>{
  await page.goto('/');await expect(page.locator('.mind-card').last()).toBeVisible();
  const last=page.locator('.mind-card').last(),id=await last.getAttribute('id');
  const before=parseFloat(await last.locator('.energy-label strong').textContent());
  await last.locator('.energy-button').click();
  await expect(page.locator(`#${id} .energy-label strong`)).toHaveText(`${Math.min(before+20,100)}%`,{timeout:10_000});
  const energy=(await page.locator('.mind-card .energy-label strong').allTextContents()).map(parseFloat);
  expect(energy).toEqual([...energy].sort((a,b)=>b-a));
});

test('social network links and genealogy search lead to real dossiers',async({page})=>{
  await page.goto('/');await page.getByRole('button',{name:'Network',exact:true}).click();
  await expect(page.locator('.network-node').first()).toBeVisible();await page.locator('.network-node').first().click();await expect(page.locator('#entity-detail')).toBeVisible();
  await page.keyboard.press('Escape');await page.getByRole('link',{name:'Dynasties',exact:true}).click();
  await page.locator('#tree-search').fill('Aurelian');await expect(page.locator('.ancestry-row')).toHaveCount(1);
  await page.locator('.ancestry-row').getByRole('link',{name:'Aurelian',exact:true}).click();await expect(page.locator('#entity-detail')).toBeVisible();
});
