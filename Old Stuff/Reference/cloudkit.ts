/**
 * CloudKit Server-to-Server Uploader
 * Ported from cloudkit_uploader.py
 * Uses node:crypto for ECDSA P-256 signing (replaces Python ecdsa lib).
 */
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { v5 as uuidv5 } from 'uuid';
import type Database from 'better-sqlite3';
import {
  updateBookCloudkitStatus,
  updatePageCloudkitStatus,
  updateCategoryCloudkitStatus,
} from './database.js';
import { normalizeLanguageCode } from '../../src/data/languages.js';

const UUID_NAMESPACE = '6ba7b810-9dad-11d1-80b4-00c04fd430c8'; // DNS namespace

export function getCloudKitLanguage(value: unknown): string {
  return normalizeLanguageCode(value);
}

function resolveGeneratedAssetPath(assetPath: string | null | undefined, bookData: Record<string, any>): string | null {
  if (!assetPath) return null;

  const generatedBooksDir = typeof bookData.generated_books_dir === 'string'
    ? path.resolve(bookData.generated_books_dir)
    : null;
  const bookGenDir = typeof bookData.book_gen_dir === 'string'
    ? path.resolve(bookData.book_gen_dir)
    : null;
  const normalized = assetPath.replace(/\\/g, '/');
  const marker = 'generated_books/';
  const candidates: string[] = [];

  if (path.isAbsolute(assetPath)) {
    candidates.push(path.resolve(assetPath));
  }

  const markerIndex = normalized.lastIndexOf(marker);
  if (markerIndex >= 0 && generatedBooksDir) {
    const relAfterMarker = normalized.slice(markerIndex + marker.length);
    candidates.push(path.resolve(generatedBooksDir, relAfterMarker));
  } else if (!path.isAbsolute(assetPath)) {
    const relPath = normalized.replace(/^\/+/, '');
    if (generatedBooksDir) candidates.push(path.resolve(generatedBooksDir, relPath));
    if (bookGenDir) candidates.push(path.resolve(bookGenDir, relPath));
  }

  return candidates.find(candidate => fs.existsSync(candidate)) ?? candidates[0] ?? null;
}

// ---------------------------------------------------------------------------
// CloudKit auth: ECDSA P-256 signature
// ---------------------------------------------------------------------------
function signRequest(
  keyPem: string,
  body: Buffer | string,
  urlPath: string,
): { timestamp: string; signature: string } {
  const bodyBuf = typeof body === 'string' ? Buffer.from(body, 'utf-8') : body;
  const timestamp = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
  const bodyHash = crypto.createHash('sha256').update(bodyBuf).digest('base64');
  const message = `${timestamp}:${bodyHash}:${urlPath}`;

  const sign = crypto.createSign('SHA256');
  sign.update(message);
  const signature = sign.sign(keyPem, 'base64');

  return { timestamp, signature };
}

interface CloudKitConfig {
  container_id: string;
  key_id: string;
  key_file: string;
}

export interface CloudKitAssetField {
  fieldName: string;
  fileData: Buffer;
}

export interface CloudKitPublicRecordUpsertResult {
  recordName: string;
  recordType: string;
  operationType: 'create' | 'update';
  skipped: boolean;
}

async function ckFetch(
  method: string,
  url: string,
  keyId: string,
  keyPem: string,
  body?: Record<string, unknown>,
): Promise<any> {
  const bodyStr = body ? JSON.stringify(body) : '';
  const parsedUrl = new URL(url);
  const urlPath = parsedUrl.pathname + parsedUrl.search;

  const { timestamp, signature } = signRequest(keyPem, bodyStr, urlPath);

  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'X-Apple-CloudKit-Request-KeyID': keyId,
    'X-Apple-CloudKit-Request-ISO8601Date': timestamp,
    'X-Apple-CloudKit-Request-SignatureV1': signature,
  };

  const res = await fetch(url, {
    method,
    headers,
    body: bodyStr || undefined,
  });

  const json = await res.json().catch(() => null);

  if (!res.ok && res.status !== 409) {
    const errorDetail = json ? JSON.stringify(json).slice(0, 500) : res.statusText;
    throw new Error(`CloudKit ${res.status}: ${errorDetail}`);
  }

  return json;
}

/**
 * Upload raw bytes to a CloudKit CKAsset field.
 * Two-step flow: request upload URL → upload binary → get receipt.
 */
async function uploadAssetForField(
  baseUrl: string,
  keyId: string,
  keyPem: string,
  recordType: string,
  recordName: string,
  fieldName: string,
  fileData: Buffer,
): Promise<Record<string, unknown>> {
  const assetsUrl = `${baseUrl}/public/assets/upload`;

  // Step 1: Request upload URL
  const tokenPayload = {
    tokens: [{
      recordName,
      recordType,
      fieldName,
    }],
  };
  const tokenRes = await ckFetch('POST', assetsUrl, keyId, keyPem, tokenPayload);
  const tokens = tokenRes?.tokens ?? [];
  if (tokens.length === 0) throw new Error(`No upload token for ${recordType}/${recordName}:${fieldName}`);

  const uploadUrl = tokens[0].url;
  if (!uploadUrl) throw new Error(`No upload URL for ${recordType}/${recordName}:${fieldName}`);

  // Step 2: Upload binary (plain POST, no CloudKit auth needed on the upload URL)
  const uploadRes = await fetch(uploadUrl, {
    method: 'POST',
    body: fileData as unknown as BodyInit,
  });
  if (!uploadRes.ok) throw new Error(`Asset upload failed: ${uploadRes.status}`);

  const uploadJson: any = await uploadRes.json();
  const singleFile = uploadJson?.singleFile;
  if (!singleFile) throw new Error(`Missing singleFile after upload for ${recordType}/${recordName}:${fieldName}`);

  return {
    fileChecksum: singleFile.fileChecksum,
    size: singleFile.size,
    receipt: singleFile.receipt,
    wrappingKey: singleFile.wrappingKey,
    referenceChecksum: singleFile.referenceChecksum,
  };
}

function recordExists(records: any[]): boolean {
  if (!records || records.length === 0) return false;
  return !('serverErrorCode' in records[0]);
}

function getCloudKitEnvironment(
  configPath: string,
  environment: string,
): { envConfig: CloudKitConfig; keyPem: string; baseUrl: string; recordsUrl: string; lookupUrl: string } {
  const normalizedEnvironment = environment === 'dev'
    ? 'development'
    : environment === 'prod'
      ? 'production'
      : environment;
  const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
  const envConfig: CloudKitConfig = config[normalizedEnvironment];
  if (!envConfig?.container_id || !envConfig?.key_id || !envConfig?.key_file) {
    throw new Error(`Missing CloudKit config for environment "${normalizedEnvironment}"`);
  }

  const keyPem = fs.readFileSync(envConfig.key_file, 'utf-8');
  const baseUrl = `https://api.apple-cloudkit.com/database/1/${envConfig.container_id}/${normalizedEnvironment}`;

  return {
    envConfig,
    keyPem,
    baseUrl,
    recordsUrl: `${baseUrl}/public/records/modify`,
    lookupUrl: `${baseUrl}/public/records/lookup`,
  };
}

/**
 * Create or update one public CloudKit record with optional CKAsset fields.
 * Used by static asset workflows that do not need the book/category DB status helpers.
 */
export async function upsertPublicRecordWithAssets(
  configPath: string,
  environment: string,
  recordType: string,
  recordName: string,
  fields: Record<string, any>,
  assetFields: CloudKitAssetField[] = [],
): Promise<CloudKitPublicRecordUpsertResult> {
  const {
    envConfig,
    keyPem,
    baseUrl,
    recordsUrl,
    lookupUrl,
  } = getCloudKitEnvironment(configPath, environment);

  const lookupRes = await ckFetch('POST', lookupUrl, envConfig.key_id, keyPem, {
    records: [{ recordName }],
  });
  const existingRecord = lookupRes?.records?.[0];
  const exists = recordExists(lookupRes?.records);

  const recordFields: Record<string, any> = { ...fields };
  for (const assetField of assetFields) {
    const asset = await uploadAssetForField(
      baseUrl,
      envConfig.key_id,
      keyPem,
      recordType,
      recordName,
      assetField.fieldName,
      assetField.fileData,
    );
    recordFields[assetField.fieldName] = { value: asset };
  }

  const operationType = exists ? 'update' : 'create';
  const record: Record<string, any> = {
    recordType,
    recordName,
    fields: recordFields,
  };
  if (exists && existingRecord?.recordChangeTag) {
    record.recordChangeTag = existingRecord.recordChangeTag;
  }

  const res = await ckFetch('POST', recordsUrl, envConfig.key_id, keyPem, {
    operations: [{ operationType, record }],
  });

  const first = res?.records?.[0];
  if (first?.serverErrorCode) {
    throw new Error(`${recordType} ${operationType} failed: ${first.serverErrorCode} - ${first.reason ?? ''}`);
  }

  return {
    recordName,
    recordType,
    operationType,
    skipped: false,
  };
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Upload a generated book (PublicBook + PublicBookPage records) to CloudKit.
 */
export async function uploadBook(
  db: Database.Database,
  configPath: string,
  environment: string,
  bookId: string,
  bookData: Record<string, any>,
  progressCallback?: (msg: string, pct: number) => void,
): Promise<boolean> {
  const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
  const envConfig: CloudKitConfig = config[environment];
  const keyPem = fs.readFileSync(envConfig.key_file, 'utf-8');

  const baseUrl = `https://api.apple-cloudkit.com/database/1/${envConfig.container_id}/${environment}`;
  const recordsUrl = `${baseUrl}/public/records/modify`;
  const lookupUrl = `${baseUrl}/public/records/lookup`;

  try {
    if (progressCallback) progressCallback('Starting CloudKit upload...', 0);

    // --- Create PublicBook record ---
    if (progressCallback) progressCallback('Creating book record...', 10);

    // Check if book already exists
    const lookupRes = await ckFetch('POST', lookupUrl, envConfig.key_id, keyPem, {
      records: [{ recordName: bookId }],
    });
    const existingBookRecord = lookupRes?.records?.[0];
    const bookExists = recordExists(lookupRes?.records);

    const storyData = bookData.story_data ?? bookData.story_json ?? {};
    const recordFields: Record<string, any> = {
      id: { value: bookId },
      title: { value: storyData.title ?? bookData.title ?? 'Generated Story' },
      author: { value: bookData.author ?? 'Book Generator' },
      createdDate: { value: bookExists && existingBookRecord?.fields?.createdDate?.value ? existingBookRecord.fields.createdDate.value : Date.now() },
      genre: { value: bookData.category_name ?? 'General' },
      illustrationStyle: { value: bookData.illustration_style ?? '' },
      userPrompt: { value: bookData.prompt ?? bookData.story_idea ?? '' },
      inputType: { value: 'book_generator' },
      numOfPagesRequested: { value: (bookData.num_pages ?? 11) * 2 },
      seed: { value: bookData.seed ?? 0 },
      isFeatured: { value: 0 },
    };
    if (bookData.category_id) recordFields.categoryID = { value: bookData.category_id };

    // age 0 = visible to all brackets; CloudKit cannot query for absent fields,
    // so always write a value rather than omitting it.
    const age = Number(bookData.age);
    recordFields.age = { value: Number.isFinite(age) && age > 0 ? age : 0 };
    recordFields.language = { value: getCloudKitLanguage(bookData.language) };

    const bookRecord: Record<string, any> = {
      recordType: 'PublicBook',
      recordName: bookId,
      fields: recordFields,
    };
    if (bookExists && existingBookRecord?.recordChangeTag) {
      bookRecord.recordChangeTag = existingBookRecord.recordChangeTag;
    }

    const operationType = bookExists ? 'update' : 'create';
    const bookModifyRes = await ckFetch('POST', recordsUrl, envConfig.key_id, keyPem, {
      operations: [{
        operationType,
        record: bookRecord,
      }],
    });

    // Check per-record error
    const first = bookModifyRes?.records?.[0];
    if (first?.serverErrorCode) {
      throw new Error(`PublicBook ${operationType} failed: ${first.serverErrorCode} - ${first.reason}`);
    }
    console.log(`${bookExists ? 'Updated' : 'Created'} PublicBook: ${bookId}`);

    // --- Create PublicBookPage records ---
    if (progressCallback) progressCallback('Creating page records...', 30);

    const storyJson = bookData.story_json ?? {};
    const coverImagePath = bookData.cover_image_path ?? bookData.cover_image_path_v3;
    const pageImages: string[] = bookData.page_images ?? [];
    const pageAudioData: Record<string, any> = bookData.page_audio_data ?? {};
    const pages = storyJson.pages ?? [];

    // Cover page (page 0)
    if (coverImagePath && fs.existsSync(coverImagePath)) {
      const coverPageId = uuidv5(`${bookId}_cover`, UUID_NAMESPACE);
      const coverLookup = await ckFetch('POST', lookupUrl, envConfig.key_id, keyPem, {
        records: [{ recordName: coverPageId }],
      });

      if (!recordExists(coverLookup?.records)) {
        const coverFields: Record<string, any> = {
          id: { value: coverPageId },
          bookID: { value: bookId },
          pageNumber: { value: 0 },
          isImagePage: { value: 1 },
          generationStatus: { value: 'completed' },
          imageDescription: { value: storyJson.coverPage ?? 'Book cover illustration' },
        };

        // Upload cover image as CKAsset
        const imageAsset = await uploadAssetForField(
          baseUrl, envConfig.key_id, keyPem,
          'PublicBookPage', coverPageId, 'imageData',
          fs.readFileSync(coverImagePath),
        );
        coverFields.imageData = { value: imageAsset };

        await ckFetch('POST', recordsUrl, envConfig.key_id, keyPem, {
          operations: [{
            operationType: 'create',
            record: { recordType: 'PublicBookPage', recordName: coverPageId, fields: coverFields },
          }],
        });
        console.log(`Created cover page: ${coverPageId}`);
      }
    }

    // Pages — v3 flow: create alternating image/text pages (matching Python v2 flow)
    // Odd page numbers (1, 3, 5, ...): image pages
    // Even page numbers (2, 4, 6, ...): text pages
    const numImages = pageImages.length;
    const numTextPages = pages.length;
    const totalPages = Math.max(numImages * 2, numTextPages * 2);

    for (let pageNum = 1; pageNum <= totalPages; pageNum++) {
      if (progressCallback) {
        const pct = 30 + Math.round(((pageNum - 1) / totalPages) * 60);
        progressCallback(`Uploading page ${pageNum}/${totalPages}...`, pct);
      }

      if (pageNum % 2 === 1) {
        // Odd page = image page
        const imageIdx = (pageNum - 1) / 2;
        if (imageIdx >= numImages) continue;

        const imagePageId = `${bookId}_image_page_${pageNum}`;

        const imgLookup = await ckFetch('POST', lookupUrl, envConfig.key_id, keyPem, {
          records: [{ recordName: imagePageId }],
        });
        if (recordExists(imgLookup?.records)) continue;

        const imgPath = pageImages[imageIdx];
        if (!imgPath || !fs.existsSync(imgPath)) {
          console.log(`Image file not found for page ${pageNum} (image index ${imageIdx}), skipping`);
          continue;
        }

        const pageFields: Record<string, any> = {
          id: { value: imagePageId },
          bookID: { value: bookId },
          pageNumber: { value: pageNum },
          isImagePage: { value: 1 },
          generationStatus: { value: 'completed' },
        };

        // Get image description from image_prompts_json if available
        const imagePromptsJson = bookData.image_prompts_json;
        let imageDescription: string | null = null;
        if (imagePromptsJson?.page_illustrations) {
          for (const illus of imagePromptsJson.page_illustrations) {
            if (illus.pageNumber === imageIdx + 1) {
              imageDescription = illus.page_image_gen_prompt ?? illus.prompt ?? illus.description ?? null;
              break;
            }
          }
        }
        pageFields.imageDescription = { value: imageDescription ?? `Page ${pageNum} illustration` };

        // Upload image as CKAsset
        const imgAsset = await uploadAssetForField(
          baseUrl, envConfig.key_id, keyPem,
          'PublicBookPage', imagePageId, 'imageData',
          fs.readFileSync(imgPath),
        );
        pageFields.imageData = { value: imgAsset };

        await ckFetch('POST', recordsUrl, envConfig.key_id, keyPem, {
          operations: [{
            operationType: 'create',
            record: { recordType: 'PublicBookPage', recordName: imagePageId, fields: pageFields },
          }],
        });
        console.log(`Created image page ${pageNum} (image index ${imageIdx})`);
      } else {
        // Even page = text page
        const textIdx = (pageNum - 2) / 2;
        if (textIdx >= numTextPages) continue;

        const page = pages[textIdx];
        const textPageId = `${bookId}_page_${pageNum}`;

        const txtLookup = await ckFetch('POST', lookupUrl, envConfig.key_id, keyPem, {
          records: [{ recordName: textPageId }],
        });
        if (recordExists(txtLookup?.records)) continue;

        const textContent = page?.text ?? '';
        const pageFields: Record<string, any> = {
          id: { value: textPageId },
          bookID: { value: bookId },
          pageNumber: { value: pageNum },
          isImagePage: { value: 0 },
          generationStatus: { value: 'completed' },
          text: { value: textContent },
        };

        // Audio — keys are based on story JSON page number (1, 2, 3, ...), not physical page number
        const storyJsonPageNum = textIdx + 1;
        const audioKey = `page_${storyJsonPageNum}`;
        let audioBytes: Buffer | null = null;
        const audioEntry = pageAudioData[audioKey];
        if (audioEntry) {
          if (Buffer.isBuffer(audioEntry)) {
            audioBytes = audioEntry;
          } else if (typeof audioEntry === 'string') {
            audioBytes = Buffer.from(audioEntry, 'base64');
          } else if (audioEntry?.audio_data) {
            audioBytes = Buffer.isBuffer(audioEntry.audio_data)
              ? audioEntry.audio_data
              : Buffer.from(audioEntry.audio_data, 'base64');
          } else if (typeof audioEntry?.audio_file_path === 'string') {
            const resolvedAudioPath = resolveGeneratedAssetPath(audioEntry.audio_file_path, bookData);
            if (resolvedAudioPath && fs.existsSync(resolvedAudioPath)) {
              audioBytes = fs.readFileSync(resolvedAudioPath);
            }
          } else if (typeof audioEntry?.audio_path === 'string') {
            const resolvedAudioPath = resolveGeneratedAssetPath(audioEntry.audio_path, bookData);
            if (resolvedAudioPath && fs.existsSync(resolvedAudioPath)) {
              audioBytes = fs.readFileSync(resolvedAudioPath);
            }
          }
        }
        if (audioBytes) {
          const audioAsset = await uploadAssetForField(
            baseUrl, envConfig.key_id, keyPem,
            'PublicBookPage', textPageId, 'pageAudioFile',
            audioBytes,
          );
          pageFields.pageAudioFile = { value: audioAsset };
          console.log(`Added audio for text page ${pageNum} (story page ${storyJsonPageNum})`);
        }

        // Word timings — stored as Bytes (base64) matching SwiftData's CD_wordTimingsJSON
        const wordTimingsData = bookData.word_timings_data;
        const pageTimings = wordTimingsData?.[`page_${storyJsonPageNum}`];
        if (pageTimings) {
          const jsonBytes = Buffer.from(JSON.stringify(pageTimings), 'utf-8');
          pageFields.wordTimingsJSON = { value: jsonBytes.toString('base64') };
          console.log(`Added word timings for text page ${pageNum} (${pageTimings.length} aligned words)`);
        }

        await ckFetch('POST', recordsUrl, envConfig.key_id, keyPem, {
          operations: [{
            operationType: 'create',
            record: { recordType: 'PublicBookPage', recordName: textPageId, fields: pageFields },
          }],
        });
        console.log(`Created text page ${pageNum} (text index ${textIdx})`);
      }
    }

    // Increment category book count
    if (!bookExists && bookData.category_id) {
      if (progressCallback) progressCallback('Updating category book count...', 95);
      await updateCategoryBookCount(baseUrl, envConfig.key_id, keyPem, bookData.category_id as string, +1);
    }

    // Update DB status
    updateBookCloudkitStatus(db, bookId, environment, 'uploaded', bookId);

    if (progressCallback) progressCallback('Upload completed successfully!', 100);
    return true;
  } catch (err: any) {
    console.error(`CloudKit upload failed: ${err.message}`);
    updateBookCloudkitStatus(db, bookId, environment, 'failed', null);
    if (progressCallback) progressCallback(`Upload failed: ${err.message}`, 0);
    return false;
  }
}

/**
 * Upload a category record to CloudKit.
 */
export async function uploadCategory(
  db: Database.Database,
  configPath: string,
  environment: string,
  category: { id: string; name: string; display_name: string; description: string; sort_order: number },
): Promise<boolean> {
  const { envConfig, keyPem, recordsUrl, lookupUrl } = getCloudKitEnvironment(configPath, environment);

  try {
    const lookupRes = await ckFetch('POST', lookupUrl, envConfig.key_id, keyPem, {
      records: [{ recordName: category.id }],
    });
    const existingRecord = lookupRes?.records?.[0];
    const exists = recordExists(lookupRes?.records);

    const fields: Record<string, any> = {
      id: { value: category.id },
      name: { value: category.name },
      displayName: { value: category.display_name },
      description: { value: category.description },
      sortOrder: { value: category.sort_order },
    };
    if (!exists) {
      fields.createdDate = { value: Date.now() };
    }

    const operationType = exists ? 'update' : 'create';
    const record: Record<string, any> = {
      recordType: 'Category',
      recordName: category.id,
      fields,
    };
    if (exists && existingRecord?.recordChangeTag) {
      record.recordChangeTag = existingRecord.recordChangeTag;
    }

    const res = await ckFetch('POST', recordsUrl, envConfig.key_id, keyPem, {
      operations: [{ operationType, record }],
    });

    const first = res?.records?.[0];
    if (first?.serverErrorCode) {
      throw new Error(`Category ${operationType} failed: ${first.serverErrorCode} - ${first.reason ?? ''}`);
    }

    updateCategoryCloudkitStatus(db, category.id, environment, 'uploaded', category.id);
    console.log(`${exists ? 'Updated' : 'Created'} category: ${category.name}`);
    return true;
  } catch (err: any) {
    console.error(`Category upload failed: ${err.message}`);
    updateCategoryCloudkitStatus(db, category.id, environment, 'failed', null);
    return false;
  }
}

/**
 * Increment or decrement the bookCount field on a Category record in CloudKit.
 * Fetches the current record (to get recordChangeTag + current count), then updates.
 */
async function updateCategoryBookCount(
  baseUrl: string,
  keyId: string,
  keyPem: string,
  categoryId: string,
  delta: number, // +1 for upload, -1 for delete
): Promise<void> {
  if (!categoryId) return;

  const lookupUrl = `${baseUrl}/public/records/lookup`;
  const recordsUrl = `${baseUrl}/public/records/modify`;

  try {
    // Fetch current Category record
    const lookupRes = await ckFetch('POST', lookupUrl, keyId, keyPem, {
      records: [{ recordName: categoryId }],
    });

    const catRec = lookupRes?.records?.[0];
    if (!catRec || catRec.serverErrorCode) {
      console.warn(`Category ${categoryId} not found in CloudKit, skipping totalBooks update`);
      return;
    }

    const currentCount = catRec.fields?.totalBooks?.value ?? 0;
    const newCount = Math.max(0, currentCount + delta);

    await ckFetch('POST', recordsUrl, keyId, keyPem, {
      operations: [{
        operationType: 'update',
        record: {
          recordType: 'Category',
          recordName: categoryId,
          recordChangeTag: catRec.recordChangeTag,
          fields: {
            totalBooks: { value: newCount },
          },
        },
      }],
    });

    console.log(`Updated Category ${categoryId} totalBooks: ${currentCount} → ${newCount}`);
  } catch (err: any) {
    console.error(`Failed to update Category totalBooks: ${err.message}`);
    // Non-fatal: don't fail the upload/delete just because count update failed
  }
}

/**
 * Delete a book and its pages from CloudKit.
 */
export async function deleteBookFromCloudKit(
  configPath: string,
  environment: string,
  bookId: string,
): Promise<boolean> {
  const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
  const envConfig: CloudKitConfig = config[environment];
  const keyPem = fs.readFileSync(envConfig.key_file, 'utf-8');

  const baseUrl = `https://api.apple-cloudkit.com/database/1/${envConfig.container_id}/${environment}`;
  const recordsUrl = `${baseUrl}/public/records/modify`;
  const queryUrl = `${baseUrl}/public/records/query`;

  try {
    // Find all pages for this book
    const queryRes = await ckFetch('POST', queryUrl, envConfig.key_id, keyPem, {
      query: {
        recordType: 'PublicBookPage',
        filterBy: [{ comparator: 'EQUALS', fieldName: 'bookID', fieldValue: { value: bookId } }],
      },
    });

    const deleteOps: any[] = [];

    // Delete pages
    const pageRecords = queryRes?.records ?? [];
    for (const rec of pageRecords) {
      if (rec.recordName) {
        deleteOps.push({
          operationType: 'delete',
          record: { recordName: rec.recordName, recordChangeTag: rec.recordChangeTag },
        });
      }
    }

    // Delete book record — must fetch recordChangeTag first
    const lookupUrl = `${baseUrl}/public/records/lookup`;
    const bookLookup = await ckFetch('POST', lookupUrl, envConfig.key_id, keyPem, {
      records: [{ recordName: bookId }],
    });
    const bookRec = bookLookup?.records?.[0];
    const categoryId = bookRec?.fields?.categoryID?.value as string | undefined;

    if (bookRec && !bookRec.serverErrorCode && bookRec.recordChangeTag) {
      deleteOps.push({
        operationType: 'delete',
        record: { recordName: bookId, recordChangeTag: bookRec.recordChangeTag },
      });
    } else {
      console.warn(`Could not get recordChangeTag for book ${bookId}, skipping book record deletion`);
    }

    if (deleteOps.length > 0) {
      await ckFetch('POST', recordsUrl, envConfig.key_id, keyPem, { operations: deleteOps });
    }

    // Decrement category book count
    if (categoryId) {
      await updateCategoryBookCount(baseUrl, envConfig.key_id, keyPem, categoryId, -1);
    }

    console.log(`Deleted book ${bookId} from CloudKit (${deleteOps.length} records)`);
    return true;
  } catch (err: any) {
    console.error(`CloudKit delete failed: ${err.message}`);
    return false;
  }
}
