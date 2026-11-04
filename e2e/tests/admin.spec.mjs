import {test,expect} from '@playwright/test'

test.use({httpCredentials:{username:'admin',password:'secret',origin:'http://127.0.0.1:4003'}})

test('LiveDashboard connects under strict CSP with nonce-authorized inline scripts',async({page})=>{
  const errors=[];page.on('pageerror',error=>errors.push(error.message));
  const response=await page.goto('/admin/dashboard');
  expect(response.headers()['content-security-policy']).toContain("'nonce-");
  expect(response.headers()['content-security-policy']).not.toContain("script-src 'self' 'unsafe-inline'");
  await expect(page.locator('.phx-connected')).toBeVisible();
  await expect(page).toHaveTitle(/LiveDashboard/);
  expect(errors).toEqual([]);
});

test('administration exposes recovery status and fits narrow screens',async({page})=>{
  await page.goto('/admin/world');
  await expect(page.locator('.phx-connected')).toBeVisible();
  await expect(page.getByRole('heading',{name:'Persistence & recovery'})).toBeVisible();
  await expect(page.locator('.operation-status')).toHaveCount(3);
  for(const width of [360,390,768,1440]){
    await page.setViewportSize({width,height:900});
    expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  }
});
