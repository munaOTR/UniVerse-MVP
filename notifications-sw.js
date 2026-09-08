/* UniVerse ICOS Web Push service worker */
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));

self.addEventListener('push',event=>{
    let data={};
    try{data=event.data?event.data.json():{}}catch(_){
        try{data={body:event.data?event.data.text():''}}catch(__){}
    }
    const title=data.title||'UniVerse ICOS';
    const options={
        body:data.body||'You have a new campus update.',
        icon:data.icon||'/favicon.ico',
        badge:data.badge||'/favicon.ico',
        tag:data.tag||`universeicos-${data.notificationId||Date.now()}`,
        renotify:true,
        data:{link:data.link||'',notificationId:data.notificationId||''},
        requireInteraction:false
    };
    event.waitUntil(self.registration.showNotification(title,options));
});

self.addEventListener('notificationclick',event=>{
    event.notification.close();
    const link=event.notification?.data?.link||'/';
    event.waitUntil((async()=>{
        const clientList=await clients.matchAll({type:'window',includeUncontrolled:true});
        const target=new URL(link, self.location.origin).href;
        for(const client of clientList){
            if('focus' in client){
                try{if(link)await client.navigate(target)}catch(_){}
                return client.focus();
            }
        }
        if(clients.openWindow)return clients.openWindow(target);
    })());
});
