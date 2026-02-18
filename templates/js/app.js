// ============================================================================
// FOTO VIEWER - CLIENT-SIDE APPLICATION
// ============================================================================

(function() {
    'use strict';
    
    // State
    let allMedia = [];
    let filteredMedia = [];
    let currentFilter = 'all';
    let currentLightboxIndex = 0;
    
    // DOM Elements
    const gallery = document.getElementById('gallery');
    const lightbox = document.getElementById('lightbox');
    const lightboxImage = document.getElementById('lightbox-image');
    const lightboxVideo = document.getElementById('lightbox-video');
    const lightboxVideoSource = document.getElementById('lightbox-video-source');
    const lightboxTitle = document.getElementById('lightbox-title');
    const lightboxDetails = document.getElementById('lightbox-details');
    const lightboxClose = document.getElementById('lightbox-close');
    const lightboxPrev = document.getElementById('lightbox-prev');
    const lightboxNext = document.getElementById('lightbox-next');
    const filterBtns = document.querySelectorAll('.filter-btn');
    
    // ========================================================================
    // INITIALIZATION
    // ========================================================================
    
    function init() {
        allMedia = window.mediaData || [];
        filteredMedia = allMedia;
        
        renderGallery();
        setupEventListeners();
    }
    
    // ========================================================================
    // GALLERY RENDERING
    // ========================================================================
    
    function renderGallery() {
        gallery.innerHTML = '';
        
        filteredMedia.forEach((item, index) => {
            const card = createMediaCard(item, index);
            gallery.appendChild(card);
        });
    }
    
    function createMediaCard(item, index) {
        const card = document.createElement('div');
        card.className = 'gallery-item';
        card.dataset.type = item.type.toLowerCase();
        card.dataset.index = index;
        
        // Thumbnail
        let thumbHTML;
        if (item.type === 'Video' && item.thumbs && item.thumbs.length > 1) {
            // Multi-Thumb für Videos
            thumbHTML = '<div class="video-thumbs">';
            item.thumbs.forEach(thumb => {
                thumbHTML += `<img src="${thumb}" alt="${item.name}">`;
            });
            thumbHTML += '</div>';
        } else {
            // Single Thumb
            const thumbSrc = item.thumbs && item.thumbs.length > 0 ? item.thumbs[0] : '/placeholder.jpg';
            thumbHTML = `<img class="item-thumb" src="${thumbSrc}" alt="${item.name}" loading="lazy">`;
        }
        
        card.innerHTML = `
            ${thumbHTML}
            <div class="item-info">
                <div class="item-name" title="${item.name}">${item.name}</div>
                <div class="item-meta">
                    <span class="item-type ${item.type.toLowerCase()}">${item.type}</span>
                    <span>${formatSize(item.size)}</span>
                </div>
            </div>
        `;
        
        card.addEventListener('click', () => openLightbox(index));
        
        return card;
    }
    
    // ========================================================================
    // FILTER
    // ========================================================================
    
    function applyFilter(filter) {
        currentFilter = filter;
        
        if (filter === 'all') {
            filteredMedia = allMedia;
        } else {
            filteredMedia = allMedia.filter(item => 
                item.type.toLowerCase() === filter
            );
        }
        
        renderGallery();
        
        // Update active button
        filterBtns.forEach(btn => {
            btn.classList.toggle('active', btn.dataset.filter === filter);
        });
    }
    
    // ========================================================================
    // LIGHTBOX
    // ========================================================================
    
    function openLightbox(index) {
        currentLightboxIndex = index;
        const item = filteredMedia[index];
        
        lightboxTitle.textContent = item.name;
        lightboxDetails.textContent = `${item.type} • ${formatSize(item.size)}`;
        
        if (item.type === 'Image') {
            lightboxImage.src = item.path;
            lightboxImage.style.display = 'block';
            lightboxVideo.style.display = 'none';
            lightboxVideo.pause();
        } else {
            lightboxVideoSource.src = item.path;
            lightboxVideo.load();
            lightboxVideo.style.display = 'block';
            lightboxImage.style.display = 'none';
        }
        
        lightbox.classList.add('active');
        document.body.style.overflow = 'hidden';
    }
    
    function closeLightbox() {
        lightbox.classList.remove('active');
        lightboxVideo.pause();
        document.body.style.overflow = '';
    }
    
    function navigateLightbox(direction) {
        currentLightboxIndex += direction;
        
        if (currentLightboxIndex < 0) {
            currentLightboxIndex = filteredMedia.length - 1;
        } else if (currentLightboxIndex >= filteredMedia.length) {
            currentLightboxIndex = 0;
        }
        
        openLightbox(currentLightboxIndex);
    }
    
    // ========================================================================
    // EVENT LISTENERS
    // ========================================================================
    
    function setupEventListeners() {
        // Filter buttons
        filterBtns.forEach(btn => {
            btn.addEventListener('click', () => {
                applyFilter(btn.dataset.filter);
            });
        });
        
        // Lightbox controls
        lightboxClose.addEventListener('click', closeLightbox);
        lightboxPrev.addEventListener('click', () => navigateLightbox(-1));
        lightboxNext.addEventListener('click', () => navigateLightbox(1));
        
        // Keyboard navigation
        document.addEventListener('keydown', (e) => {
            if (!lightbox.classList.contains('active')) return;
            
            switch(e.key) {
                case 'Escape':
                    closeLightbox();
                    break;
                case 'ArrowLeft':
                    navigateLightbox(-1);
                    break;
                case 'ArrowRight':
                    navigateLightbox(1);
                    break;
            }
        });
        
        // Close on background click
        lightbox.addEventListener('click', (e) => {
            if (e.target === lightbox) {
                closeLightbox();
            }
        });
    }
    
    // ========================================================================
    // UTILITIES
    // ========================================================================
    
    function formatSize(bytes) {
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
        if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
        return (bytes / (1024 * 1024 * 1024)).toFixed(1) + ' GB';
    }
    
    // ========================================================================
    // START
    // ========================================================================
    
    document.addEventListener('DOMContentLoaded', init);
    
})();