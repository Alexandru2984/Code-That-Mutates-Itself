export function downloadText(content,name,type='application/json'){
  const url=URL.createObjectURL(new Blob([content],{type})),link=document.createElement('a')
  link.href=url;link.download=name;link.hidden=true;document.body.append(link)
  try{link.click()}finally{link.remove();setTimeout(()=>URL.revokeObjectURL(url),5000)}
}
