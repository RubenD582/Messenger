// imageStorage.js - Industry-standard image storage with compression
const sharp = require('sharp');
const fs = require('fs').promises;
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const mime = require('mime-types');

class ImageStorage {
  constructor() {
    this.uploadsDir = path.join(__dirname, '../uploads/remixes');
    this.baseUrl = process.env.BASE_URL || 'http://localhost:3000';

    // Compression settings
    this.settings = {
      base: {
        quality: 95, // Increased from 85 to reduce quality loss during merging
        format: 'jpeg',
        maxWidth: 1920,
        maxHeight: 1920,
      },
      thumbnail: {
        quality: 80,
        format: 'jpeg',
        maxWidth: 400,
        maxHeight: 400,
      },
    };
  }

  /**
   * Initialize storage - create directories if they don't exist
   */
  async init() {
    try {
      await fs.mkdir(this.uploadsDir, { recursive: true });
      await fs.mkdir(path.join(this.uploadsDir, 'thumbnails'), { recursive: true });
      console.log('✅ Image storage initialized');
    } catch (error) {
      console.error('❌ Error initializing image storage:', error);
      throw error;
    }
  }

  /**
   * Upload and optimize image
   * @param {Buffer} buffer - Image buffer
   * @param {Object} options - Upload options
   * @returns {Promise<Object>} - Image URLs and metadata
   */
  async uploadImage(buffer, options = {}) {
    try {
      const imageId = uuidv4();
      const timestamp = Date.now();

      // Get image metadata
      const metadata = await sharp(buffer).metadata();

      // Process base image (compressed)
      const baseFilename = `${imageId}_${timestamp}.jpg`;
      const basePath = path.join(this.uploadsDir, baseFilename);

      await sharp(buffer)
        .resize(this.settings.base.maxWidth, this.settings.base.maxHeight, {
          fit: 'inside',
          withoutEnlargement: true,
        })
        .jpeg({
          quality: this.settings.base.quality,
          progressive: true,
          mozjpeg: true // Better compression
        })
        .toFile(basePath);

      // Generate thumbnail
      const thumbnailFilename = `${imageId}_${timestamp}_thumb.jpg`;
      const thumbnailPath = path.join(this.uploadsDir, 'thumbnails', thumbnailFilename);

      await sharp(buffer)
        .resize(this.settings.thumbnail.maxWidth, this.settings.thumbnail.maxHeight, {
          fit: 'cover',
          position: 'center',
        })
        .jpeg({
          quality: this.settings.thumbnail.quality,
          progressive: true,
        })
        .toFile(thumbnailPath);

      // Get file sizes
      const baseStats = await fs.stat(basePath);
      const thumbStats = await fs.stat(thumbnailPath);

      const result = {
        imageId,
        originalUrl: `/uploads/remixes/${baseFilename}`,
        thumbnailUrl: `/uploads/remixes/thumbnails/${thumbnailFilename}`,
        width: metadata.width,
        height: metadata.height,
        size: baseStats.size,
        thumbnailSize: thumbStats.size,
        format: 'jpeg',
      };

      console.log(`✅ Uploaded image ${imageId}: ${(baseStats.size / 1024).toFixed(2)}KB (original: ${(buffer.length / 1024).toFixed(2)}KB)`);

      return result;
    } catch (error) {
      console.error('❌ Error uploading image:', error);
      throw new Error('Failed to upload image');
    }
  }

  /**
   * Delete image and thumbnail
   * @param {string} imageId - Image ID to delete
   */
  async deleteImage(imageId) {
    try {
      const files = await fs.readdir(this.uploadsDir);
      const thumbnails = await fs.readdir(path.join(this.uploadsDir, 'thumbnails'));

      // Delete base image
      const baseFile = files.find(f => f.startsWith(imageId));
      if (baseFile) {
        await fs.unlink(path.join(this.uploadsDir, baseFile));
      }

      // Delete thumbnail
      const thumbFile = thumbnails.find(f => f.startsWith(imageId));
      if (thumbFile) {
        await fs.unlink(path.join(this.uploadsDir, 'thumbnails', thumbFile));
      }

      console.log(`✅ Deleted image ${imageId}`);
    } catch (error) {
      console.error('❌ Error deleting image:', error);
      // Don't throw - deletion failures shouldn't block the request
    }
  }

  /**
   * Clean up old images (for maintenance)
   * @param {number} daysOld - Delete images older than this many days
   */
  async cleanupOldImages(daysOld = 30) {
    try {
      const now = Date.now();
      const maxAge = daysOld * 24 * 60 * 60 * 1000;

      const files = await fs.readdir(this.uploadsDir);
      let deletedCount = 0;

      for (const file of files) {
        if (file === 'thumbnails') continue;

        const filePath = path.join(this.uploadsDir, file);
        const stats = await fs.stat(filePath);

        if (now - stats.mtimeMs > maxAge) {
          await fs.unlink(filePath);
          deletedCount++;

          // Also delete thumbnail
          const imageId = file.split('_')[0];
          await this.deleteImage(imageId);
        }
      }

      console.log(`✅ Cleaned up ${deletedCount} old images`);
      return deletedCount;
    } catch (error) {
      console.error('❌ Error cleaning up images:', error);
      throw error;
    }
  }
}

// Export singleton instance
const imageStorage = new ImageStorage();

module.exports = imageStorage;
