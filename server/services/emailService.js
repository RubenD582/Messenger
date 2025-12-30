const nodemailer = require('nodemailer');
const winston = require('winston');

const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(winston.format.timestamp(), winston.format.json()),
  transports: [
    new winston.transports.Console(),
    new winston.transports.File({ filename: 'logs/combined.log' }),
  ],
});

class EmailService {
  constructor() {
    this.transporter = null;
    this.initializeTransporter();
  }

  /**
   * Initialize email transporter
   * Uses environment variables for configuration
   */
  initializeTransporter() {
    const emailConfig = {
      host: process.env.SMTP_HOST || 'smtp.gmail.com',
      port: parseInt(process.env.SMTP_PORT || '587'),
      secure: process.env.SMTP_SECURE === 'true', // true for 465, false for other ports
      auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASSWORD,
      },
    };

    // For development: log emails to console if SMTP not configured
    if (!process.env.SMTP_USER || !process.env.SMTP_PASSWORD) {
      logger.warn('SMTP credentials not configured. Using console logging for development.');
      this.transporter = nodemailer.createTransport({
        streamTransport: true,
        newline: 'unix',
        buffer: true,
      });
    } else {
      this.transporter = nodemailer.createTransport(emailConfig);
      logger.info('Email transporter initialized');
    }
  }

  /**
   * Send OTP email
   * @param {string} to - Recipient email address
   * @param {string} otp - OTP code
   * @param {string} purpose - 'registration' or 'login' or '2fa'
   * @returns {Promise<Object>} Send result
   */
  async sendOTP(to, otp, purpose = 'registration') {
    try {
      const subject = this.getSubject(purpose);
      const html = this.getEmailTemplate(otp, purpose);

      const mailOptions = {
        from: process.env.SMTP_FROM || '"Messenger App" <noreply@messenger.app>',
        to,
        subject,
        html,
      };

      // For development without SMTP: log to console
      if (!process.env.SMTP_USER || !process.env.SMTP_PASSWORD) {
        logger.info('='.repeat(60));
        logger.info('EMAIL WOULD BE SENT (Development Mode)');
        logger.info(`To: ${to}`);
        logger.info(`Subject: ${subject}`);
        logger.info(`OTP Code: ${otp}`);
        logger.info('='.repeat(60));

        return {
          success: true,
          messageId: 'dev-mode-' + Date.now(),
          devMode: true,
        };
      }

      const info = await this.transporter.sendMail(mailOptions);
      logger.info(`OTP email sent to ${to}: ${info.messageId}`);

      return {
        success: true,
        messageId: info.messageId,
      };
    } catch (error) {
      logger.error('Error sending OTP email:', error);
      return {
        success: false,
        error: 'Failed to send OTP email',
      };
    }
  }

  /**
   * Get email subject based on purpose
   * @param {string} purpose
   * @returns {string} Email subject
   */
  getSubject(purpose) {
    switch (purpose) {
      case 'registration':
        return 'Verify Your Email - Messenger App';
      case 'login':
        return 'Your Login Code - Messenger App';
      case '2fa':
        return 'Two-Factor Authentication Code - Messenger App';
      default:
        return 'Your Verification Code - Messenger App';
    }
  }

  /**
   * Get HTML email template
   * @param {string} otp - OTP code
   * @param {string} purpose
   * @returns {string} HTML template
   */
  getEmailTemplate(otp, purpose) {
    const title = purpose === 'registration'
      ? 'Verify Your Email'
      : purpose === 'login'
      ? 'Login Verification'
      : 'Two-Factor Authentication';

    const message = purpose === 'registration'
      ? 'Thank you for signing up! Please use the code below to verify your email address.'
      : purpose === 'login'
      ? 'Use the code below to complete your login.'
      : 'Use the code below to complete two-factor authentication.';

    return `
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>${title}</title>
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            background-color: #f4f4f4;
            margin: 0;
            padding: 0;
          }
          .container {
            max-width: 600px;
            margin: 40px auto;
            background: #ffffff;
            border-radius: 12px;
            overflow: hidden;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
          }
          .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 30px 20px;
            text-align: center;
            color: #ffffff;
          }
          .header h1 {
            margin: 0;
            font-size: 24px;
            font-weight: 600;
          }
          .content {
            padding: 40px 30px;
          }
          .message {
            font-size: 16px;
            color: #555;
            margin-bottom: 30px;
            text-align: center;
          }
          .otp-container {
            background: #f8f9fa;
            border: 2px solid #e9ecef;
            border-radius: 8px;
            padding: 20px;
            text-align: center;
            margin: 30px 0;
          }
          .otp-code {
            font-size: 36px;
            font-weight: bold;
            letter-spacing: 8px;
            color: #667eea;
            font-family: 'Courier New', monospace;
          }
          .expiry {
            font-size: 14px;
            color: #6c757d;
            margin-top: 20px;
            text-align: center;
          }
          .warning {
            background: #fff3cd;
            border-left: 4px solid #ffc107;
            padding: 15px;
            margin: 20px 0;
            font-size: 14px;
            color: #856404;
          }
          .footer {
            background: #f8f9fa;
            padding: 20px;
            text-align: center;
            font-size: 12px;
            color: #6c757d;
            border-top: 1px solid #e9ecef;
          }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1>${title}</h1>
          </div>
          <div class="content">
            <p class="message">${message}</p>

            <div class="otp-container">
              <div class="otp-code">${otp}</div>
            </div>

            <p class="expiry">
              This code will expire in <strong>10 minutes</strong>.
            </p>

            <div class="warning">
              <strong>Security Notice:</strong> Never share this code with anyone. Our team will never ask for your verification code.
            </div>
          </div>
          <div class="footer">
            <p>If you didn't request this code, please ignore this email.</p>
            <p>&copy; ${new Date().getFullYear()} Messenger App. All rights reserved.</p>
          </div>
        </div>
      </body>
      </html>
    `;
  }

  /**
   * Send password reset email
   * @param {string} to - Recipient email
   * @param {string} resetToken - Password reset token
   * @returns {Promise<Object>} Send result
   */
  async sendPasswordReset(to, resetToken) {
    try {
      const resetLink = `${process.env.FRONTEND_URL || 'http://localhost:3000'}/reset-password?token=${resetToken}`;

      const mailOptions = {
        from: process.env.SMTP_FROM || '"Messenger App" <noreply@messenger.app>',
        to,
        subject: 'Password Reset Request - Messenger App',
        html: `
          <!DOCTYPE html>
          <html>
          <head>
            <meta charset="utf-8">
            <style>
              body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
              .container { max-width: 600px; margin: 40px auto; padding: 20px; }
              .button {
                display: inline-block;
                padding: 12px 24px;
                background: #667eea;
                color: #ffffff;
                text-decoration: none;
                border-radius: 6px;
                margin: 20px 0;
              }
            </style>
          </head>
          <body>
            <div class="container">
              <h2>Password Reset Request</h2>
              <p>You requested to reset your password. Click the button below to proceed:</p>
              <a href="${resetLink}" class="button">Reset Password</a>
              <p>This link will expire in 1 hour.</p>
              <p>If you didn't request this, please ignore this email.</p>
            </div>
          </body>
          </html>
        `,
      };

      const info = await this.transporter.sendMail(mailOptions);
      logger.info(`Password reset email sent to ${to}: ${info.messageId}`);

      return {
        success: true,
        messageId: info.messageId,
      };
    } catch (error) {
      logger.error('Error sending password reset email:', error);
      return {
        success: false,
        error: 'Failed to send password reset email',
      };
    }
  }
}

module.exports = new EmailService();
