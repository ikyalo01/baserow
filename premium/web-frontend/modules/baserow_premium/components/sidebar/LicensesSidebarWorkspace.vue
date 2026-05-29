<template>
  <nuxt-link
    v-if="isStaff"
    v-slot="{ href, navigate, isExactActive }"
    custom
    :to="{ name: 'admin-licenses' }"
  >
    <li class="tree__item" :class="{ active: isExactActive }">
      <div class="tree__action">
        <a :href="href" class="tree__link" @click="navigate">
          <i class="tree__icon iconoir-shield-check"></i>
          <span class="tree__link-text">{{
            $t('premium.adminType.licenses')
          }}</span>
        </a>
      </div>
    </li>
  </nuxt-link>
</template>

<script>
export default {
  name: 'LicensesSidebarWorkspace',
  props: {
    workspace: {
      type: Object,
      required: true,
    },
  },
  computed: {
    isStaff() {
      return this.$store.getters['auth/isStaff']
    },
  },
}
</script>
