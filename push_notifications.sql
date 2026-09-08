-- UniVerse ICOS: production notification pipeline
-- 1) Stores browser push subscriptions safely.
-- 2) Generates user-targeted notification rows for core MVP activities.
-- 3) A Supabase Database Webhook on public.notifications INSERT should call
--    the send-push Edge Function included with this package.

create table if not exists public.push_subscriptions (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    endpoint text not null unique,
    p256dh text,
    auth text,
    subscription jsonb not null,
    user_agent text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists push_subscriptions_user_id_idx on public.push_subscriptions(user_id);

alter table public.push_subscriptions enable row level security;

drop policy if exists "Users can read own push subscriptions" on public.push_subscriptions;
create policy "Users can read own push subscriptions"
on public.push_subscriptions for select to authenticated
using (auth.uid()=user_id);

drop policy if exists "Users can insert own push subscriptions" on public.push_subscriptions;
create policy "Users can insert own push subscriptions"
on public.push_subscriptions for insert to authenticated
with check (auth.uid()=user_id);

drop policy if exists "Users can update own push subscriptions" on public.push_subscriptions;
create policy "Users can update own push subscriptions"
on public.push_subscriptions for update to authenticated
using (auth.uid()=user_id) with check (auth.uid()=user_id);

drop policy if exists "Users can delete own push subscriptions" on public.push_subscriptions;
create policy "Users can delete own push subscriptions"
on public.push_subscriptions for delete to authenticated
using (auth.uid()=user_id);

-- Keep updated_at fresh without requiring the client to know the policy.
create or replace function public.universeicos_touch_push_subscription()
returns trigger
language plpgsql
as $$
begin
  new.updated_at=now();
  return new;
end;
$$;

drop trigger if exists trg_universeicos_push_subscription_updated on public.push_subscriptions;
create trigger trg_universeicos_push_subscription_updated
before update on public.push_subscriptions
for each row execute function public.universeicos_touch_push_subscription();

-- Generic notification helper. It is SECURITY DEFINER so database-triggered
-- notifications are created regardless of end-user INSERT policies.
create or replace function public.universeicos_create_notification(
  p_user_id uuid,
  p_type text,
  p_actor_id uuid,
  p_title text,
  p_body text,
  p_link text default null
)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if p_user_id is null then return; end if;
  insert into public.notifications(user_id,type,actor_id,title,body,link,is_read,created_at)
  values(p_user_id,p_type,p_actor_id,left(coalesce(p_title,''),160),left(coalesce(p_body,''),1000),p_link,false,now());
end;
$$;

-- Direct messages: notify every other member of the conversation.
create or replace function public.universeicos_notify_message()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  member record;
  sender_name text;
  preview text;
begin
  select coalesce(full_name,'Student') into sender_name from public.profiles where id=new.sender_id limit 1;
  preview=left(regexp_replace(coalesce(new.content,''),'\s+',' ','g'),140);
  for member in
    select user_id from public.conversation_members
    where conversation_id=new.conversation_id and user_id<>new.sender_id
  loop
    perform public.universeicos_create_notification(
      member.user_id,'campus_message',new.sender_id,
      sender_name,
      case when preview='' then 'Sent you a new message.' else preview end,
      '#chat-conversation-'||new.conversation_id
    );
  end loop;
  return new;
end;
$$;

drop trigger if exists trg_universeicos_message_notification on public.messages;
create trigger trg_universeicos_message_notification
after insert on public.messages
for each row execute function public.universeicos_notify_message();

-- Message requests: notify the recipient.
create or replace function public.universeicos_notify_message_request()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare sender_name text;
begin
  select coalesce(full_name,'Student') into sender_name from public.profiles where id=new.sender_id limit 1;
  perform public.universeicos_create_notification(
    new.recipient_id,'message_request',new.sender_id,
    'New message request',
    coalesce(sender_name,'A student')||' sent you a message request.',
    '#chat-requests'
  );
  return new;
end;
$$;

drop trigger if exists trg_universeicos_message_request_notification on public.message_requests;
create trigger trg_universeicos_message_request_notification
after insert on public.message_requests
for each row execute function public.universeicos_notify_message_request();

-- Orbit likes: notify the post owner, never the actor.
create or replace function public.universeicos_notify_orbit_like()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare owner_id uuid; actor_name text;
begin
  select poster_id into owner_id from public.orbit_feed where id=new.post_id limit 1;
  if owner_id is null or owner_id=new.user_id then return new; end if;
  select coalesce(full_name,'Student') into actor_name from public.profiles where id=new.user_id limit 1;
  perform public.universeicos_create_notification(owner_id,'orbit_like',new.user_id,'New reaction',coalesce(actor_name,'A student')||' liked your campus post.','#orbit-post-'||new.post_id);
  return new;
end;
$$;

drop trigger if exists trg_universeicos_orbit_like_notification on public.orbit_post_likes;
create trigger trg_universeicos_orbit_like_notification
after insert on public.orbit_post_likes
for each row execute function public.universeicos_notify_orbit_like();

-- Orbit comments: notify the post owner, never the commenter.
create or replace function public.universeicos_notify_orbit_comment()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare owner_id uuid; actor_name text; preview text;
begin
  select poster_id into owner_id from public.orbit_feed where id=new.post_id limit 1;
  if owner_id is null or owner_id=new.user_id then return new; end if;
  select coalesce(full_name,'Student') into actor_name from public.profiles where id=new.user_id limit 1;
  preview=left(regexp_replace(coalesce(new.content,''),'\s+',' ','g'),120);
  perform public.universeicos_create_notification(owner_id,'orbit_comment',new.user_id,'New comment',coalesce(actor_name,'A student')||' commented: '||preview,'#orbit-post-'||new.post_id);
  return new;
end;
$$;

drop trigger if exists trg_universeicos_orbit_comment_notification on public.orbit_comments;
create trigger trg_universeicos_orbit_comment_notification
after insert on public.orbit_comments
for each row execute function public.universeicos_notify_orbit_comment();

-- Orbit @mentions: notify each mentioned user.
create or replace function public.universeicos_notify_orbit_mention()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare actor_id uuid; actor_name text;
begin
  select poster_id into actor_id from public.orbit_feed where id=new.post_id limit 1;
  if actor_id is null or actor_id=new.mentioned_user_id then return new; end if;
  select coalesce(full_name,'Student') into actor_name from public.profiles where id=actor_id limit 1;
  perform public.universeicos_create_notification(new.mentioned_user_id,'orbit_mention',actor_id,'You were mentioned',coalesce(actor_name,'A student')||' mentioned you in a campus post.','#orbit-post-'||new.post_id);
  return new;
end;
$$;

drop trigger if exists trg_universeicos_orbit_mention_notification on public.orbit_post_mentions;
create trigger trg_universeicos_orbit_mention_notification
after insert on public.orbit_post_mentions
for each row execute function public.universeicos_notify_orbit_mention();

-- Important: do not notify every campus user for every new post. That would be
-- noisy and is intentionally left to targeted/following/announcement workflows.
