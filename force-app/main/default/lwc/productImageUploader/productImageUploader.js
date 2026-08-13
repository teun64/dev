import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCurrentImageUrl from '@salesforce/apex/Ctrl_ProductImageManager.getCurrentImageUrl';
import uploadProductImage from '@salesforce/apex/Ctrl_ProductImageManager.uploadProductImage';

const MAX_FILE_SIZE = 5 * 1024 * 1024; // 5MB - comfortably under the Apex request-size limit

// There's no supported way to read Salesforce's Comfy/Compact density setting from inside an
// LWC's shadow DOM - it isn't exposed as a public CSS token or API. Instead, react to the
// component's own rendered width: below this, there isn't room for the large preview next to the
// text/button, which is what a squeezed/compact layout actually looks like in practice.
const COMPACT_WIDTH_THRESHOLD = 480;

export default class ProductImageUploader extends LightningElement {
    @api recordId;

    @track currentImageUrl;
    @track isDragging = false;
    @track isUploading = false;
    @track isCompact = false;
    removeOldFile = true;

    _resizeObserver;

    connectedCallback() {
        this.loadCurrentImage();
    }

    renderedCallback() {
        if (!this._resizeObserver) {
            const el = this.template.querySelector('.pi-card');
            if (el) {
                this._resizeObserver = new ResizeObserver((entries) => {
                    const width = entries[0].contentRect.width;
                    const compact = width < COMPACT_WIDTH_THRESHOLD;
                    if (compact !== this.isCompact) {
                        this.isCompact = compact;
                    }
                });
                this._resizeObserver.observe(el);
            }
        }
    }

    disconnectedCallback() {
        if (this._resizeObserver) {
            this._resizeObserver.disconnect();
            this._resizeObserver = null;
        }
    }

    loadCurrentImage() {
        getCurrentImageUrl({ productId: this.recordId })
            .then((url) => {
                this.currentImageUrl = url;
            })
            .catch(() => {
                this.currentImageUrl = null;
            });
    }

    get hasCurrentImage() {
        return !!this.currentImageUrl;
    }

    get cardTitle() {
        return `Webshop Image (${this.hasCurrentImage ? 1 : 0})`;
    }

    get dropZoneClass() {
        return 'drop-zone'
            + (this.isDragging ? ' drop-zone--dragging' : '')
            + (this.isCompact ? ' drop-zone--compact' : '');
    }

    get rowFigureClass() {
        return 'row-figure' + (this.isCompact ? ' row-figure--compact' : '');
    }

    get placeholderIconSize() {
        return this.isCompact ? 'small' : 'large';
    }

    handleRemoveOldFileChange(event) {
        this.removeOldFile = event.target.checked;
    }

    handleDragOver(event) {
        event.preventDefault();
        this.isDragging = true;
    }

    handleDragLeave() {
        this.isDragging = false;
    }

    handleDrop(event) {
        event.preventDefault();
        this.isDragging = false;
        const files = event.dataTransfer && event.dataTransfer.files;
        if (files && files.length > 0) {
            this.processFile(files[0]);
        }
    }

    handleFileInputChange(event) {
        const files = event.target.files;
        if (files && files.length > 0) {
            this.processFile(files[0]);
        }
        event.target.value = '';
    }

    handleBrowseClick() {
        this.template.querySelector('[data-id="fileInput"]').click();
    }

    handleUploadButtonClick(event) {
        event.stopPropagation();
        this.handleBrowseClick();
    }

    processFile(file) {
        if (!file.type || !file.type.startsWith('image/')) {
            this.showToast('Error', 'Only image files are supported.', 'error');
            return;
        }
        if (file.size > MAX_FILE_SIZE) {
            this.showToast('Error', 'Image is too large - max 5MB.', 'error');
            return;
        }

        this.isUploading = true;
        const reader = new FileReader();
        reader.onload = () => {
            const base64 = reader.result.split(',')[1];
            uploadProductImage({
                productId: this.recordId,
                base64Data: base64,
                filename: file.name,
                removeOldFile: this.removeOldFile
            })
                .then((downloadUrl) => {
                    this.currentImageUrl = downloadUrl;
                    this.showToast('Success', 'Product image updated.', 'success');
                })
                .catch((error) => {
                    const message = (error.body && error.body.message) || 'Failed to upload image.';
                    this.showToast('Error', message, 'error');
                })
                .finally(() => {
                    this.isUploading = false;
                });
        };
        reader.onerror = () => {
            this.isUploading = false;
            this.showToast('Error', 'Could not read the selected file.', 'error');
        };
        reader.readAsDataURL(file);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
