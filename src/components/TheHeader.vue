<template>
  <header class="relative z-20 p-2 sm:p-3 md:p-4 bg-base-300 flex gap-2 sm:gap-3 md:gap-4 justify-center w-full shadow-lg">
    <input
        ref="fileInput"
        type="file"
        accept=".csv,.txt,text/csv,text/plain"
        class="hidden"
        @change="handleFileSelection"
    />
    <form @submit.prevent="handleSubmit" class="join w-full min-w-0 max-w-155 grow" autocomplete="off">
      <input
          v-model="url"
          id="queue-url-input"
          name="URL input to queue a video or playlist"
          class="input join-item w-full min-w-0"
          :placeholder="inputPlaceholder"
          type="text"
          inputmode="url"
          autocomplete="off"
          autocorrect="off"
          autocapitalize="off"
          spellcheck="false"
          ref="input"
      />
      <button
          type="button"
          class="btn btn-secondary join-item"
          title="Paste clipboard URL and add it to the queue"
          :disabled="isAdding"
          @click="handlePasteAndAdd"
      >
        {{ isAdding ? 'Adding…' : 'Paste' }}
      </button>
      <base-button-dropdown
          btnClass="btn-primary"
          placement="bottom"
          align="end"
          menuWidthClass="w-64"
          flushLeft
          hideMain
          :caretAriaLabel="t('layout.header.actions.more')"
      >
        <li>
          <button
              class="gap-2 text-nowrap"
              :class="{ 'font-semibold text-primary': watchClipboardStore.isActive }"
              type="button"
              :aria-pressed="watchClipboardStore.isActive"
              @click="watchClipboardStore.toggle()"
          >
            <clipboard-document-check-icon v-if="watchClipboardStore.isActive" class="w-4 h-4" />
            <clipboard-document-list-icon v-else class="w-4 h-4" />
            {{ t(watchClipboardStore.isActive ? 'layout.header.actions.watchClipboardStop' : 'layout.header.actions.watchClipboardStart') }}
          </button>
        </li>
        <li>
          <button class="gap-2 text-nowrap" type="button" @click="handleImportClick">
            <document-arrow-up-icon class="w-4 h-4" />
            {{ t('layout.header.actions.importFile') }}
          </button>
        </li>
        <li>
          <button
            class="gap-2 text-nowrap"
            :class="{ 'font-semibold text-primary': hasActiveInputFilters }"
            type="button"
            @click="openInputFilters"
          >
            <funnel-icon v-if="!hasActiveInputFilters" class="w-4 h-4" />
            <funnel-icon-solid v-else class="w-4 h-4" />
            {{ t('layout.header.actions.inputFilters') }}
          </button>
        </li>
      </base-button-dropdown>
    </form>
    <router-link class="btn btn-subtle btn-sm self-center md:btn-md" :title="t('layout.header.nav.settings')" :to="{ name: 'settings.downloads' }">
      <span class="sr-only">{{ t('layout.header.nav.settings') }}</span>
      <cog8-tooth-icon class="w-6 h-6"/>
    </router-link>
  </header>
</template>

<script setup lang="ts">

import {
  ClipboardDocumentCheckIcon,
  ClipboardDocumentListIcon,
  Cog8ToothIcon,
  DocumentArrowUpIcon,
  FunnelIcon,
} from '@heroicons/vue/24/outline';
import { FunnelIcon as FunnelIconSolid } from '@heroicons/vue/24/solid';
import { readText } from '@tauri-apps/plugin-clipboard-manager';
import { useMediaStore } from '../stores/media/media';
import { useMediaGroupStore } from '../stores/media/group';
import { ref, computed, onMounted, watch } from 'vue';
import { useClipboard } from '../composables/useClipboard';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useSettingsStore } from '../stores/settings';
import { isValidUrl } from '../helpers/url.ts';
import BaseButtonDropdown from './base/BaseButtonDropdown.vue';
import { useWatchClipboardStore } from '../stores/watchClipboard.ts';
import { useToastStore } from '../stores/toast.ts';
import {
  getUrlImportReadErrorToast,
  getUrlImportToast,
  isSupportedImportFile,
  parseUrlFileText,
  parseUrlInputText,
} from '../helpers/urlImport.ts';
import { isInputFiltersActive } from '../helpers/inputFilters.ts';

const { t } = useI18n();
const router = useRouter();
const mediaStore = useMediaStore();
const mediaGroupStore = useMediaGroupStore();
const toastStore = useToastStore();

const settingsStore = useSettingsStore();
const watchClipboardStore = useWatchClipboardStore();

const doPolling = computed(() => settingsStore.settings.input.autoFillClipboard || watchClipboardStore.isActive);
const hasActiveInputFilters = computed(() => isInputFiltersActive(settingsStore.settings.inputFilters));

const { content: clipboardContent, poll } = useClipboard({
  doPolling,
});

const input = ref<HTMLInputElement | null>(null);
const fileInput = ref<HTMLInputElement | null>(null);
const fileImportImmediateDownload = ref(false);
const isAdding = ref(false);

const inputPlaceholder = computed(() => {
  if (watchClipboardStore.isActive) {
    return t('layout.header.watchClipboardPlaceholder');
  }
  const defaultPlaceholder = t('layout.header.placeholder');
  if (clipboardHasValidUrl.value) {
    return clipboardContent.value ?? defaultPlaceholder;
  } else {
    return defaultPlaceholder;
  }
});

const clipboardHasValidUrl = computed(() => isValidUrl(clipboardContent));

const url = ref('');

function queueUrlKey(rawUrl: string): string {
  const trimmed = rawUrl.trim();
  try {
    const parsed = new URL(trimmed);
    const host = parsed.hostname.toLowerCase().replace(/^www\./, '');
    const isYouTubeHost = host === 'youtube.com'
      || host.endsWith('.youtube.com')
      || host === 'youtube-nocookie.com'
      || host.endsWith('.youtube-nocookie.com')
      || host === 'youtu.be';

    if (isYouTubeHost) {
      const playlistId = parsed.searchParams.get('list');
      if (playlistId) return `youtube-playlist:${playlistId}`;

      if (host === 'youtu.be') {
        const videoId = parsed.pathname.split('/').filter(Boolean)[0];
        if (videoId) return `youtube-video:${videoId}`;
      }

      const pathParts = parsed.pathname.split('/').filter(Boolean);
      const videoId = parsed.pathname === '/watch'
        ? parsed.searchParams.get('v')
        : (['shorts', 'live', 'embed'].includes(pathParts[0]) ? pathParts[1] : null);
      if (videoId) return `youtube-video:${videoId}`;
    }

    parsed.hash = '';
    return parsed.toString();
  } catch {
    return trimmed;
  }
}

function filterDuplicateUrls(urls: string[]) {
  const existingKeys = new Set(
    mediaGroupStore.orderedGroups
      .map(group => queueUrlKey(group.url))
      .filter(Boolean),
  );
  const batchKeys = new Set<string>();
  let duplicates = 0;

  const uniqueUrls = urls.filter((candidate) => {
    const key = queueUrlKey(candidate);
    if (existingKeys.has(key) || batchKeys.has(key)) {
      duplicates++;
      return false;
    }
    batchKeys.add(key);
    return true;
  });

  return { uniqueUrls, duplicates };
}

async function addClipboardUrlToQueue(urlToRecord: string) {
  if (!watchClipboardStore.isActive || !isValidUrl(urlToRecord) || watchClipboardStore.hasSeen(urlToRecord)) {
    return;
  }

  watchClipboardStore.markSeen(urlToRecord);
  const { uniqueUrls, duplicates } = filterDuplicateUrls([urlToRecord]);
  if (duplicates > 0) {
    toastStore.showToast('Already in queue. Duplicate link skipped.', { style: 'info' });
    return;
  }
  await mediaStore.addUrlBatch(uniqueUrls);
}

async function addFromInput(immediateDownload: boolean = false) {
  if (isAdding.value) return;
  const urlToSubmit = url.value.length > 0 ? url.value : clipboardContent.value;
  if (!urlToSubmit) return;

  isAdding.value = true;
  try {
    await processParsedUrls(parseUrlInputText(urlToSubmit), immediateDownload, true);
    await router.push('/');
    url.value = '';
  } finally {
    isAdding.value = false;
  }
}

async function handlePasteAndAdd() {
  if (isAdding.value) return;
  isAdding.value = true;
  try {
    const clipboardText = (await readText()).trim();
    if (!clipboardText) return;
    url.value = clipboardText;
    await processParsedUrls(parseUrlInputText(clipboardText), false, true);
    await router.push('/');
    url.value = '';
  } catch (e) {
    console.error('Failed to read clipboard:', e);
  } finally {
    isAdding.value = false;
  }
}

async function processParsedUrls(
  result: { urls: string[]; skipped: number },
  immediateDownload: boolean = false,
  fromInput: boolean = false,
) {
  const { uniqueUrls, duplicates } = filterDuplicateUrls(result.urls);

  if (duplicates > 0) {
    const message = duplicates === 1
      ? 'Already in queue. Duplicate link skipped.'
      : `${duplicates} duplicate links were already in the queue and were skipped.`;
    toastStore.showToast(message, { style: 'info' });
  }

  if (uniqueUrls.length > 0) {
    if (immediateDownload) {
      await mediaStore.addUrlBatchAndDownload(uniqueUrls, false, true);
    } else {
      await mediaStore.addUrlBatch(uniqueUrls);
    }
  }

  if (!fromInput || result.urls.length > 1) {
    const toast = getUrlImportToast({ urls: uniqueUrls, skipped: result.skipped });
    toastStore.showToast(toast.message, { style: toast.style });
  }
}

function handleSubmit() {
  void addFromInput();
}

function handleImportClick(event: MouseEvent) {
  fileImportImmediateDownload.value = event.shiftKey;
  fileInput.value?.click();
}

function openInputFilters() {
  void router.push({ name: 'input-filters' });
}

async function handleFileSelection(event: Event) {
  const target = event.target as HTMLInputElement;
  const file = target.files?.[0];
  target.value = '';

  if (!file || !isSupportedImportFile(file)) {
    const toast = getUrlImportToast({ urls: [], skipped: 0 });
    toastStore.showToast(toast.message, { style: toast.style });
    return;
  }

  try {
    const text = await file.text();
    await processParsedUrls(parseUrlFileText(text), fileImportImmediateDownload.value);
  } catch {
    const toast = getUrlImportReadErrorToast();
    toastStore.showToast(toast.message, { style: toast.style });
  } finally {
    fileImportImmediateDownload.value = false;
  }
}

onMounted(() => {
  input.value?.focus();
});

watch(clipboardContent, (value) => {
  if (!value) return;
  void addClipboardUrlToQueue(value);
});

watch(() => watchClipboardStore.isActive, (isActive) => {
  if (!isActive) return;
  poll();
  const currentClipboard = clipboardContent.value;
  if (!currentClipboard) return;
  void addClipboardUrlToQueue(currentClipboard);
});

</script>
